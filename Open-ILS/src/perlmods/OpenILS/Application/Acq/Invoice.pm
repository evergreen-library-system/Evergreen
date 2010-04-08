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
            } elsif($entry->isdeleted) {
                # TODO set encumbrance=true for related fund_debit and revert back to estimated price
                $e->delete_acq_invoice_entry($entry) or return $e->die_event;
            } elsif($entry->ischanged) {
                # TODO: update the related fund_debit
                $e->update_acq_invoice_entry($entry) or return $e->die_event;
            }
        }
    }

    if($items) {
        for my $item (@$items) {
            $item->invoice($invoice->id);
            if($item->isnew) {
                $e->create_acq_invoice_item($item) or return $e->die_event;
            } elsif($item->isdeleted) {
                if($item->fund_debit) {
                    $e->delete_acq_fund_debit(
                        $e->retrieve_acq_fund_debit($item->fund_debit)
                    ) or return $e->die_event;
                }
                $e->delete_acq_invoice_item($item) or return $e->die_event;
            } elsif($item->ischanged) {
                # TODO: update related fund debit
                $e->update_acq_invoice_item($item) or return $e->die_event;
            }
        }
    }

    $invoice = fetch_invoice_impl($e, $invoice->id);
    $e->commit;

    return $invoice;
}

__PACKAGE__->register_method(
	method => 'build_invoice_api',
	api_name	=> 'open-ils.acq.invoice.retrieve',
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
                "acqie" => ["lineitem", "purchase_order"],
                "acqii" => ["fund_debit"],
                "jub" => ["attributes", "lineitem_details"],
                "acqlid" => ["fund_debit"]
            }
        }
    ];

    my $invoice = $e->retrieve_acq_invoice($args);
    return $invoice if $options->{no_flesh_misc} or $options->{keep_li_marc};

    $_->lineitem->clear_marc for @{$invoice->entries};
    return $invoice;
}

__PACKAGE__->register_method(
	method => 'process_invoice',
	api_name	=> 'open-ils.acq.invoice.process',
	signature => {
        desc => q/
            Process an invoice.  This updates the related fund debits by applying the now known cost
            and sets the encumbrance flag to false.  It creates new debits for ad-hoc expenditures (invoice_item's).
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


sub process_invoice {
    my($self, $conn, $auth, $invoice_id) = @_;

    my $e = new_editor(xact => 1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $invoice = fetch_invoice_impl($e, $invoice_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('CREATE_INVOICE', $invoice->receiver);

    my %fund_totals;

    for my $entry (@{$invoice->entries}) {
        
        my $debits = $e->json_query({
            select => {acqfdeb => ['id']},
            from => {
                acqfdeb => {
                    acqlid => {
                        filter => {cancel_reason => undef, recv_time => {'!=' => undef}},
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
            where => {'+acqfdeb' => {encumbrance => 't'}},
            order_by => {'acqlid' => ['recv_time']},
            limit => $entry->phys_item_count
        });

        next unless @$debits;

        if($entry->phys_item_count > @$debits) {
            $e->rollback;
            # We can't invoice for more items than we have debits for
            return OpenILS::Event->new(
                'ACQ_INVOICE_ENTRY_COUNT_EXCEEDS_DEBITS', payload => {entry => $entry->id});
        }

        my $item_cost = $entry->cost_billed;
        unless($U->is_true($entry->billed_per_item)) {
            # cost billed is for the whole set of items.  Get the
            # per-item cost by dividing the total cost by total invoiced
            $item_cost = $item_cost / $entry->inv_item_count;
        }

        for my $debit_id (map { $_->{id} } @$debits) {
            my $debit = $e->retrieve_acq_fund_debit($debit_id);
            $debit->amount($item_cost);
            $debit->encumbrance('f');
            $e->update_acq_fund_debit($debit) or return $e->die_event;
            $fund_totals{$debit->fund} ||= 0;
            $fund_totals{$debit->fund} += $item_cost;
        }
    }

    my $total_entry_cost = 0;
    $total_entry_cost += $fund_totals{$_} for keys %fund_totals;

    $logger->info("invoice: total bib cost for invoice = $total_entry_cost");

    for my $item (@{$invoice->items}) {

        # future: cache item types locally
        my $item_type = $e->retrieve_acq_invoice_item_type($item->inv_item_type) or return $e->die_event;
        
        if($U->is_true($item_type->prorate)) {

            # Charge prorated across applicable funds
            my $full_item_cost = $item->cost_billed;
            my $first_round = 1;
            my $largest_debit;
            my $total_debited = 0;

            for my $fund_id (keys %fund_totals) {

                my $spent_for_fund = $fund_totals{$fund_id};
                next unless $spent_for_fund > 0;

                my $prorated_amount = ($spent_for_fund / $total_entry_cost) * $full_item_cost;
                $logger->info("invoice: attaching prorated amount $prorated_amount to fund $fund_id for invoice $invoice_id");

                my $debit = Fieldmapper::acq::fund_debit->new;
                $debit->fund($fund_id);
                $debit->amount($prorated_amount);
                $debit->origin_amount($prorated_amount);
                $debit->origin_currency_type($e->retrieve_acq_fund($fund_id)->currency_type); # future: cache funds locally
                $debit->encumbrance('f');
                $debit->debit_type('prorated_charge');
                $e->create_acq_fund_debit($debit) or return $e->die_event;
                $total_debited += $prorated_amount;
                $largest_debit = $debit if !$largest_debit or $debit->amount > $largest_debit->amount;

                if($first_round) {

                    # re-purpose the original invoice_item for the first prorated amount
                    $item->fund_debit($debit->id);
                    $item->cost_billed($prorated_amount);
                    $e->update_acq_invoice_item($item) or return $e->die_event;

                } else {

                    # for subsequent prorated amounts, create a new invoice_item
                    my $new_item = $item->clone;
                    $new_item->clear_id;
                    $new_item->fund_debit($debit->id);
                    $new_item->cost_billed($prorated_amount);
                    $e->create_acq_invoice_item($new_item) or return $e->die_event;
                }

                $first_round = 0;
            }

            # make sure the percentages didn't leave a small sliver of money over/under-debited
            if($total_debited != $full_item_cost) {
                $logger->info("invoice: found prorate descrepency. total_debited=$total_debited; total_cost=$full_item_cost; difference ". ($full_item_cost - $total_debited));
                # tweak the largest debit to smooth out the difference
                $largest_debit = $e->retrieve_acq_fund_debit($largest_debit); # get latest copy
                $largest_debit->amount( $largest_debit->amount + ($full_item_cost - $total_debited) );
                $largest_debit->origin_amount($largest_debit->amount);
                $e->update_acq_fund_debit($largest_debit) or return $e->die_event;
            }

        } else { # not prorated
            
            # Direct charge against a fund

            next if $item->fund_debit; 

            unless($item->fund) {
                $e->rollback;
                return OpenILS::Event->new('ACQ_INVOICE_ITEM_REQUIRES_FUND', payload => {item => $item->id});
            }

            my $debit = Fieldmapper::acq::fund_debit->new;
            $debit->fund($item->fund);
            $debit->amount($item->cost_billed);
            $debit->origin_amount($item->cost_billed);
            $debit->origin_currency_type($e->retrieve_acq_fund($item->fund)->currency_type); # future: cache funds locally
            $debit->encumbrance('f');
            $debit->debit_type('direct_charge');
            $e->create_acq_fund_debit($debit) or return $e->die_event;

            $item->fund_debit($debit->id);
            $e->update_acq_invoice_item($item) or return $e->die_event;
        }
    }

    $invoice = fetch_invoice_impl($e, $invoice_id);
    $e->commit;

    return $invoice;

}


1;
