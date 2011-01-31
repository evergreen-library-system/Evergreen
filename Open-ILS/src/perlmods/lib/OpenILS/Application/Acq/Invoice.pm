package OpenILS::Application::Acq::Invoice;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
my $U = 'OpenILS::Application::AppUtils';


__PACKAGE__->register_method(
	method => 'build_invoice_api',
	api_name	=> 'open-ils.acq.invoice.update',
	signature => {
        desc => q/Creates, updates, and deletes invoices, and related invoice entries, and invoice items/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice/, type => 'number'},
            {desc => q/Entries.  Array of 'acqie' objects/, type => 'array'},
            {desc => q/Items.  Array of 'acqii' objects/, type => 'array'},
        ],
        return => {desc => 'The invoice w/ entries and items attached', type => 'object', class => 'acqinv'}
    }
);

sub build_invoice_api {
    my($self, $conn, $auth, $invoice, $entries, $items) = @_;

    my $e = new_editor(xact => 1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $evt;

    if(ref $invoice) {
        if($invoice->isnew) {
            $invoice->receiver($e->requestor->ws_ou) unless $invoice->receiver;
            $invoice->recv_method('PPR') unless $invoice->recv_method;
            $invoice->recv_date('now') unless $invoice->recv_date;
            $e->create_acq_invoice($invoice) or return $e->die_event;
        } elsif($invoice->isdeleted) {
            i$e->delete_acq_invoice($invoice) or return $e->die_event;
        } else {
            $e->update_acq_invoice($invoice) or return $e->die_event;
        }
    } else {
        # caller only provided the ID
        $invoice = $e->retrieve_acq_invoice($invoice) or return $e->die_event;
    }

    return $e->die_event unless $e->allowed('CREATE_INVOICE', $invoice->receiver);

    if($entries) {
        for my $entry (@$entries) {
            $entry->invoice($invoice->id);

            if($entry->isnew) {

                $e->create_acq_invoice_entry($entry) or return $e->die_event;
                return $evt if $evt = update_entry_debits($e, $entry);

            } elsif($entry->isdeleted) {

                return $evt if $evt = rollback_entry_debits($e, $entry); 
                $e->delete_acq_invoice_entry($entry) or return $e->die_event;

            } elsif($entry->ischanged) {

                my $orig_entry = $e->retrieve_acq_invoice_entry($entry->id) or return $e->die_event;

                if($orig_entry->amount_paid != $entry->amount_paid or 
                        $entry->phys_item_count != $orig_entry->phys_item_count) {

                    return $evt if $evt = rollback_entry_debits($e, $orig_entry); 
                    return $evt if $evt = update_entry_debits($e, $entry);

                }

                $e->update_acq_invoice_entry($entry) or return $e->die_event;
            }
        }
    }

    if($items) {
        for my $item (@$items) {
            $item->invoice($invoice->id);

            if($item->isnew) {

                $e->create_acq_invoice_item($item) or return $e->die_event;

                # future: cache item types
                my $item_type = $e->retrieve_acq_invoice_item_type(
                    $item->inv_item_type) or return $e->die_event;

                # prorated items are handled separately
                unless($U->is_true($item_type->prorate)) {
                    my $debit;
                    if($item->po_item) {
                        my $po_item = $e->retrieve_acq_po_item($item->po_item) or return $e->die_event;
                        $debit = $e->retrieve_acq_fund_debit($po_item->fund_debit) or return $e->die_event;
                    } else {
                        $debit = Fieldmapper::acq::fund_debit->new;
                        $debit->isnew(1);
                    }
                    $debit->fund($item->fund);
                    $debit->amount($item->amount_paid);
                    $debit->origin_amount($item->amount_paid);
                    $debit->origin_currency_type($e->retrieve_acq_fund($item->fund)->currency_type); # future: cache funds locally
                    $debit->encumbrance('f');
                    $debit->debit_type('direct_charge');

                    if($debit->isnew) {
                        $e->create_acq_fund_debit($debit) or return $e->die_event;
                    } else {
                        $e->update_acq_fund_debit($debit) or return $e->die_event;
                    }

                    $item->fund_debit($debit->id);
                    $e->update_acq_invoice_item($item) or return $e->die_event;
                }

            } elsif($item->isdeleted) {

                $e->delete_acq_invoice_item($item) or return $e->die_event;

                if($item->po_item and $e->retrieve_acq_po_item($item->po_item)->fund_debit == $item->fund_debit) {
                    # the debit is attached to the po_item.  instead of deleting it, roll it back 
                    # to being an encumbrance.  Note: a prorated invoice_item that points to a po_item 
                    # could point to a different fund_debit.  We can't go back in time to collect all the
                    # prorated invoice_items (nor is the caller asking us too), so when that happens, 
                    # just delete the extraneous debit (in the else block).
                    my $debit = $e->retrieve_acq_fund_debit($item->fund_debit);
                    $debit->encumbrance('t');
                    $e->update_acq_fund_debit($debit) or return $e->die_event;
                } else {
                    $e->delete_acq_fund_debit($e->retrieve_acq_fund_debit($item->fund_debit))
                        or return $e->die_event;
                }


            } elsif($item->ischanged) {

                my $debit = $e->retrieve_acq_fund_debit($item->fund_debit) or return $e->die_event;
                $debit->amount($item->amount_paid);
                $debit->fund($item->fund);
                $e->update_acq_fund_debit($debit) or return $e->die_event;
                $e->update_acq_invoice_item($item) or return $e->die_event;
            }
        }
    }

    $invoice = fetch_invoice_impl($e, $invoice->id);
    $e->commit;

    return $invoice;
}


sub rollback_entry_debits {
    my($e, $entry) = @_;
    my $debits = find_entry_debits($e, $entry, 'f', entry_amount_per_item($entry));
    my $lineitem = $e->retrieve_acq_lineitem($entry->lineitem) or return $e->die_event;

    for my $debit (@$debits) {
        # revert to the original estimated amount re-encumber
        $debit->encumbrance('t');
        $debit->amount($lineitem->estimated_unit_price());
        $e->update_acq_fund_debit($debit) or return $e->die_event;
        update_copy_cost($e, $debit) or return $e->die_event; # clear the cost
    }

    return undef;
}

sub update_entry_debits {
    my($e, $entry) = @_;

    my $debits = find_entry_debits($e, $entry, 't');
    return undef unless @$debits;

    if($entry->phys_item_count > @$debits) {
        $e->rollback;
        # We can't invoice for more items than we have debits for
        return OpenILS::Event->new(
            'ACQ_INVOICE_ENTRY_COUNT_EXCEEDS_DEBITS', 
            payload => {entry => $entry->id});
    }

    for my $debit (@$debits) {
        my $amount = entry_amount_per_item($entry);
        $debit->amount($amount);
        $debit->encumbrance('f');
        $e->update_acq_fund_debit($debit) or return $e->die_event;

        # TODO: this does not reflect ancillary charges, like taxes, etc.
        # We may need a way to indicate whether the amount attached to an 
        # invoice_item should be prorated and included in the copy cost.
        # Note that acq.invoice_item_type.prorate does not necessarily 
        # mean a charge should be included in the copy price, only that 
        # it should spread accross funds.
        update_copy_cost($e, $debit, $amount) or return $e->die_event;
    }

    return undef;
}

# update the linked copy to reflect the amount paid for the item
# returns true on success, false on error
sub update_copy_cost {
    my ($e, $debit, $amount) = @_;

    my $lid = $e->search_acq_lineitem_detail([
        {fund_debit => $debit->id},
        {flesh => 1, flesh_fields => {acqlid => ['eg_copy_id']}}
    ])->[0];

    if($lid and my $copy = $lid->eg_copy_id) {
        defined $amount and $copy->cost($amount) or $copy->clear_cost;
        $copy->editor($e->requestor->id);
        $copy->edit_date('now');
        $e->update_asset_copy($copy) or return 0;
    }

    return 1;
}


sub entry_amount_per_item {
    my $entry = shift;
    return $entry->amount_paid if $U->is_true($entry->billed_per_item);
    return 0 if $entry->phys_item_count == 0;
    return $entry->amount_paid / $entry->phys_item_count;
}

sub easy_money { # TODO XXX replace with something from a library
    my ($val) = @_;

    my $rounded = int($val * 100) / 100.0;
    if ($rounded == $val) {
        return sprintf("%.02f", $val);
    } else {
        return sprintf("%g", $val);
    }
}

# 0 on failure (caller should call $e->die_event), array on success
sub amounts_spent_per_fund {
    my ($e, $inv_id) = @_;

    my $entries = $e->search_acq_invoice_entry({"invoice" => $inv_id}) or
        return 0;

    my $items = $e->search_acq_invoice_item({"invoice" => $inv_id}) or
        return 0;

    my %totals_by_fund;
    foreach my $entry (@$entries) {
        my $debits = find_entry_debits($e, $entry, "f") or return 0;
        foreach (@$debits) {
            $totals_by_fund{$_->fund} ||= 0.0;
            $totals_by_fund{$_->fund} += $_->amount;
        }
    }

    foreach my $item (@$items) {
        next unless $item->fund and $item->amount_paid;
        $totals_by_fund{$item->fund} ||= 0.0;
        $totals_by_fund{$item->fund} += $item->amount_paid;
    }

    my @totals;
    foreach my $fund_id (keys %totals_by_fund) {
        my $fund = $e->retrieve_acq_fund($fund_id) or return 0;
        push @totals, {
            "fund" => $fund->to_bare_hash,
            "total" => easy_money($totals_by_fund{$fund_id})
        };
    }

    return \@totals;
}

# there is no direct link between invoice_entry and fund debits.
# when we need to retrieve the related debits, we have to do some searching
sub find_entry_debits {
    my($e, $entry, $encumbrance, $amount) = @_;

    my $query = {
        select => {acqfdeb => ['id']},
        from => {
            acqfdeb => {
                acqlid => {
                    join => {
                        jub =>  {
                            join => {
                                acqie => {
                                    filter => {id => $entry->id}
                                }
                            }
                        }
                    }
                }
            }
        },
        where => {'+acqfdeb' => {encumbrance => $encumbrance}},
        order_by => {'acqlid' => ['recv_time']}, # un-received items will sort to the end
        limit => $entry->phys_item_count
    };

    $query->{where}->{'+acqfdeb'}->{amount} = $amount if $amount;

    my $debits = $e->json_query($query);
    my $debit_ids = [map { $_->{id} } @$debits];
    return (@$debit_ids) ? $e->search_acq_fund_debit({id => $debit_ids}) : [];
}


__PACKAGE__->register_method(
	method => 'build_invoice_api',
	api_name	=> 'open-ils.acq.invoice.retrieve',
    authoritative => 1,
	signature => {
        desc => q/Creates a new stub invoice/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice Id/, type => 'number'},
        ],
        return => {desc => 'The new invoice w/ entries and items attached', type => 'object', class => 'acqinv'}
    }
);


sub fetch_invoice_api {
    my($self, $conn, $auth, $invoice_id, $options) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $invoice = fetch_invoice_impl($e, $invoice_id, $options) or
        return $e->event;
    return $e->event unless $e->allowed(['VIEW_INVOICE', 'CREATE_INVOICE'], $invoice->receiver);

    return $invoice;
}

sub fetch_invoice_impl {
    my ($e, $invoice_id, $options) = @_;

    $options ||= {};

    my $args = $options->{"no_flesh_misc"} ? $invoice_id : [
        $invoice_id,
        {
            "flesh" => 6,
            "flesh_fields" => {
                "acqinv" => ["entries", "items"],
                "acqii" => ["fund_debit", "purchase_order", "po_item"]
            }
        }
    ];

    return $e->retrieve_acq_invoice($args);
}

__PACKAGE__->register_method(
	method => 'prorate_invoice',
	api_name	=> 'open-ils.acq.invoice.apply_prorate',
	signature => {
        desc => q/
            For all invoice items that have the prorate flag set to true, this will create the necessary 
            additional invoice_item's to prorate the cost across all affected funds by percent spent for each fund.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice Id/, type => 'number'},
        ],
        return => {desc => 'The updated invoice w/ entries and items attached', type => 'object', class => 'acqinv'}
    }
);


sub prorate_invoice {
    my($self, $conn, $auth, $invoice_id) = @_;

    my $e = new_editor(xact => 1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $invoice = fetch_invoice_impl($e, $invoice_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('CREATE_INVOICE', $invoice->receiver);

    my @lid_debits;
    push(@lid_debits, @{find_entry_debits($e, $_, 'f', entry_amount_per_item($_))}) for @{$invoice->entries};

    my $inv_items = $e->search_acq_invoice_item([
        {"invoice" => $invoice_id, "fund_debit" => {"!=" => undef}},
        {"flesh" => 1, "flesh_fields" => {"acqii" => ["fund_debit"]}}
    ]) or return $e->die_event;

    my @item_debits = map { $_->fund_debit } @$inv_items;

    my %fund_totals;
    my $total_entry_paid = 0;
    for my $debit (@lid_debits, @item_debits) {
        $fund_totals{$debit->fund} = 0 unless $fund_totals{$debit->fund};
        $fund_totals{$debit->fund} += $debit->amount;
        $total_entry_paid += $debit->amount;
    }

    $logger->info("invoice: prorating against invoice amount $total_entry_paid");

    for my $item (@{$invoice->items}) {

        next if $item->fund_debit; # item has already been processed

        # future: cache item types locally
        my $item_type = $e->retrieve_acq_invoice_item_type($item->inv_item_type) or return $e->die_event;
        next unless $U->is_true($item_type->prorate);

        # Prorate charges across applicable funds
        my $full_item_paid = $item->amount_paid; # total amount paid for this item before splitting
        my $full_item_cost = $item->cost_billed; # total amount invoiced for this item before splitting
        my $first_round = 1;
        my $largest_debit;
        my $largest_item;
        my $total_debited = 0;
        my $total_costed = 0;

        for my $fund_id (keys %fund_totals) {

            my $spent_for_fund = $fund_totals{$fund_id};
            next unless $spent_for_fund > 0;

            my $prorated_amount = ($spent_for_fund / $total_entry_paid) * $full_item_paid;
            my $prorated_cost = ($spent_for_fund / $total_entry_paid) * $full_item_cost;
            $logger->info("invoice: attaching prorated amount $prorated_amount to fund $fund_id for invoice $invoice_id");

            my $debit;
            if($first_round and $item->po_item) {
                # if this item is the result of a PO item, repurpose the original debit
                # for the first chunk of the prorated amount
                $debit = $e->retrieve_acq_fund_debit($item->po_item->fund_debit);
            } else {
                $debit = Fieldmapper::acq::fund_debit->new;
                $debit->isnew(1);
            }

            $debit->fund($fund_id);
            $debit->amount($prorated_amount);
            $debit->origin_amount($prorated_amount);
            $debit->origin_currency_type($e->retrieve_acq_fund($fund_id)->currency_type); # future: cache funds locally
            $debit->encumbrance('f');
            $debit->debit_type('prorated_charge');

            if($debit->isnew) {
                $e->create_acq_fund_debit($debit) or return $e->die_event;
            } else {
                $e->update_acq_fund_debit($debit) or return $e->die_event;
            }

            $total_debited += $prorated_amount;
            $total_costed += $prorated_cost;
            $largest_debit = $debit if !$largest_debit or $prorated_amount > $largest_debit->amount;

            if($first_round) {

                # re-purpose the original invoice_item for the first prorated amount
                $item->fund($fund_id);
                $item->fund_debit($debit->id);
                $item->amount_paid($prorated_amount);
                $item->cost_billed($prorated_cost);
                $e->update_acq_invoice_item($item) or return $e->die_event;
                $largest_item = $item if !$largest_item or $prorated_amount > $largest_item->amount_paid;

            } else {

                # for subsequent prorated amounts, create a new invoice_item
                my $new_item = $item->clone;
                $new_item->clear_id;
                $new_item->fund($fund_id);
                $new_item->fund_debit($debit->id);
                $new_item->amount_paid($prorated_amount);
                $new_item->cost_billed($prorated_cost);
                $e->create_acq_invoice_item($new_item) or return $e->die_event;
                $largest_item = $new_item if !$largest_item or $prorated_amount > $largest_item->amount_paid;
            }

            $first_round = 0;
        }

        # make sure the percentages didn't leave a small sliver of money over/under-debited
        # if so, tweak the largest debit to smooth out the difference
        if($total_debited != $full_item_paid or $total_costed != $full_item_cost) {
            
            my $paid_diff = $full_item_paid - $total_debited;
            my $cost_diff = $full_item_cost - $total_debited;
            $logger->info("invoice: repairing prorate descrepency of paid:$paid_diff and cost:$cost_diff");
            my $new_paid = $largest_item->amount_paid + $paid_diff;
            my $new_cost = $largest_item->cost_billed + $cost_diff;

            $largest_debit = $e->retrieve_acq_fund_debit($largest_debit->id); # get latest copy
            $largest_debit->amount($new_paid);
            $e->update_acq_fund_debit($largest_debit) or return $e->die_event;

            $largest_item = $e->retrieve_acq_invoice_item($largest_item->id); # get latest copy
            $largest_item->amount_paid($new_paid);
            $largest_item->cost_billed($new_cost);

            $e->update_acq_invoice_item($largest_item) or return $e->die_event;
        }
    }

    $invoice = fetch_invoice_impl($e, $invoice_id);
    $e->commit;

    return $invoice;
}


__PACKAGE__->register_method(
    method      => "print_html_invoice",
    api_name    => "open-ils.acq.invoice.print.html",
    stream      => 1,
    signature   => {
        desc    => "Retrieve printable HTML vouchers for each given invoice",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Invoice ID or a list of them", type => "mixed"},
        ],
        return => {
            desc => q{One A/T event containing a printable HTML voucher for
                each given invoice},
            type => "object", class => "atev"}
    }
);


sub print_html_invoice {
    my ($self, $conn, $auth, $id_list) = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    $id_list = [$id_list] unless ref $id_list;

    my $invoices = $e->search_acq_invoice({"id" => $id_list}) or
        return $e->die_event;

    foreach my $invoice (@$invoices) {
        return $e->die_event unless
            $e->allowed("VIEW_INVOICE", $invoice->receiver);

        my $amounts = amounts_spent_per_fund($e, $invoice->id) or
            return $e->die_event;

        $conn->respond(
            $U->fire_object_event(
                undef, "format.acqinv.html", $invoice, $invoice->receiver,
                "print-on-demand", $amounts
            )
        );
    }

    $e->disconnect;
    undef;
}

1;
