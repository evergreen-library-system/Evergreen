package OpenILS::Application::Acq::Invoice;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Acq::Order;
use OpenILS::Event;
my $U = 'OpenILS::Application::AppUtils';


# return nothing on success, event on failure
sub _prepare_fund_debit_for_inv_item {
    my ($debit, $item, $e, $inv_closing) = @_;

    $debit->fund($item->fund);
    $debit->amount($item->amount_paid);
    $debit->origin_amount($item->amount_paid);

    # future: cache funds locally
    my $fund = $e->retrieve_acq_fund($item->fund) or return $e->die_event;

    $debit->origin_currency_type($fund->currency_type);
    $debit->encumbrance($inv_closing ? 'f' : 't');
    $debit->debit_type('direct_charge');

    return;
}

__PACKAGE__->register_method(
    method => 'build_invoice_api',
    api_name    => 'open-ils.acq.invoice.update',
    signature => {
        desc => q/Creates, updates, and deletes invoices, and related invoice entries, and invoice items/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice/, type => 'number'},
            {desc => q/Entries.  Array of 'acqie' objects/, type => 'array'},
            {desc => q/Items.  Array of 'acqii' objects/, type => 'array'},
            {desc => q/Finalize PO's.  Array of 'acqpo' ID's/, type => 'array'},
        ],
        return => {desc => 'The invoice w/ entries and items attached', type => 'object', class => 'acqinv'}
    }
);

__PACKAGE__->register_method(
    method => 'build_invoice_api',
    api_name    => 'open-ils.acq.invoice.update.fleshed',
    signature => {
        desc => q/Creates, updates, and deletes invoices, and related invoice entries, and invoice items/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice/, type => 'number'},
            {desc => q/Entries.  Array of 'acqie' objects/, type => 'array'},
            {desc => q/Items.  Array of 'acqii' objects/, type => 'array'},
            {desc => q/Finalize PO's.  Array of 'acqpo' ID's/, type => 'array'},
        ],
        return => {desc => 'The invoice w/ entries and items attached, and providers fleshed.', type => 'object', class => 'acqinv'}
    }
);

__PACKAGE__->register_method(
    method => 'build_invoice_api',
    api_name    => 'open-ils.acq.invoice.update.fleshed.dry_run',
    signature => {
        desc => q/Goes through the motion of creating, updating, and deleting invoices, and related invoice entries, and invoice items, returning intermediate events as normal, but does not commit to the database at the end./,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice/, type => 'number'},
            {desc => q/Entries.  Array of 'acqie' objects/, type => 'array'},
            {desc => q/Items.  Array of 'acqii' objects/, type => 'array'},
            {desc => q/Finalize PO's.  Array of 'acqpo' ID's/, type => 'array'},
        ],
        return => {desc => 'The invoice w/ entries and items attached, and providers fleshed.', type => 'object', class => 'acqinv'}
    }
);

__PACKAGE__->register_method(
    method => 'build_invoice_api',
    api_name    => 'open-ils.acq.invoice.update.fleshed.override',
    signature => {
        desc => q/Creates, updates, and deletes invoices, and related invoice entries, and invoice items. Overrides certain events./,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice/, type => 'number'},
            {desc => q/Entries.  Array of 'acqie' objects/, type => 'array'},
            {desc => q/Items.  Array of 'acqii' objects/, type => 'array'},
            {desc => q/Finalize PO's.  Array of 'acqpo' ID's/, type => 'array'},
        ],
        return => {desc => 'The invoice w/ entries and items attached, and providers fleshed.', type => 'object', class => 'acqinv'}
    }
);

sub build_invoice_impl {
    my ($e, $invoice, $entries, $items, $do_commit, $finalize_pos, $fully_fleshed, $override, $fund_check) = @_;

    $finalize_pos ||= [];

    # for comparing with updated fund totals right before the $do_commit check,
    # so we can do stop/warn threshold checks
    my %orig_fund_totals = ();
    # if invoice is new, we won't have initial totals
    # also, this is an uber method, so only do these fund checks with update.fleshed
    # dojo acq uses ordinary update without the .fleshed
    if ($fund_check) {
        if ($invoice->isnew) {
                $logger->info("fund check: for invoice save, pre-business logic: new invoice");
        } else {
            $logger->info("fund check: for invoice save, pre-business logic: existing invoice");
            my $orig_fund_summary = amounts_spent_per_fund($e, $invoice->id, $e->authtoken);
            use Data::Dumper;
            $Data::Dumper::Indent = 0;  # No newlines and default indentation
            $Data::Dumper::Terse  = 1;  # No variable names where feasible
            $logger->info("fund check: pre, summary = " . Dumper($orig_fund_summary));

            # Loop through each hash in the array
            foreach my $fund_entry (@$orig_fund_summary) {
                # Extract the fund ID and total
                my $fund_id = $fund_entry->{'fund'}->{'id'};
                my $total   = $fund_entry->{'total'};

                $logger->info("fund check: for invoice save, pre-business logic: fund $fund_id total $total");
                # Add to our hash
                $orig_fund_totals{$fund_id} = $total;
            }
        }
    }

    my $inv_closing = 0;
    my $inv_reopening = 0;

    if ($invoice->isnew) {
        $invoice->recv_method('PPR') unless $invoice->recv_method;
        $invoice->recv_date('now') unless $invoice->recv_date;
        if ($invoice->close_date) {
            $inv_closing = 1;
            $invoice->closed_by($e->requestor->id);
        }
        $e->create_acq_invoice($invoice) or return $e->die_event;
    } elsif ($invoice->isdeleted) {
        $e->delete_acq_invoice($invoice) or return $e->die_event;
    } else {
        my $orig_inv = $e->retrieve_acq_invoice($invoice->id)
            or return $e->die_event;

        if (!$orig_inv->close_date && $invoice->close_date) {
            $inv_closing = 1;
            $invoice->closed_by($e->requestor->id);

        } elsif ($orig_inv->close_date && !$invoice->close_date) {
            $inv_reopening = 1;
            $invoice->clear_closed_by;
        }

        $e->update_acq_invoice($invoice) or return $e->die_event;
    }

    my $evt;

    if ($entries) {
        for my $entry (@$entries) {
            $entry->invoice($invoice->id);

            if ($entry->isnew) {
                $e->create_acq_invoice_entry($entry) or return $e->die_event;
                return $evt if $evt = uncancel_copies_as_needed($e, $entry);
                return $evt if $evt = update_entry_debits(
                    $e, $entry, 'unlinked', $inv_closing, $inv_reopening, $override);
            } elsif ($entry->isdeleted) {
                # XXX Deleting entries does not recancel anything previously
                # uncanceled.
                return $evt if $evt = rollback_entry_debits($e, $entry);
                $e->delete_acq_invoice_entry($entry) or return $e->die_event;
            } elsif ($entry->ischanged) {
                my $orig_entry = $e->retrieve_acq_invoice_entry($entry->id) or
                    return $e->die_event;

                if ($orig_entry->amount_paid != $entry->amount_paid or
                    $entry->phys_item_count != $orig_entry->phys_item_count) {
                    return $evt if $evt = rollback_entry_debits(
                        $e, $orig_entry, $orig_entry);

                    # XXX Updates can only uncancel more LIDs when
                    # phys_item_count goes up, but cannot recancel them when
                    # phys_item_count goes down.
                    return $evt if $evt = uncancel_copies_as_needed($e, $entry);

                    # debits were rolled back (encumbrance=t) above, so now 
                    # search for un-invoiced, potentially linked debits 
                    # to (re-) invoice.
                    return $evt if $evt = update_entry_debits(
                        $e, $entry, 'all', $inv_closing, $inv_reopening, $override);
                }

                $e->update_acq_invoice_entry($entry) or return $e->die_event;
            }
        }
    }

    if ($items) {
        for my $item (@$items) {
            $item->invoice($invoice->id);
                
            # future: cache item types
            my $item_type = $e->retrieve_acq_invoice_item_type(
                $item->inv_item_type) or return $e->die_event;

            if ($item->isnew) {
                $e->create_acq_invoice_item($item) or return $e->die_event;


                # This following complex conditional statement effecively means:
                #   1) Items with item_types that are prorate are handled
                #       differently.
                #   2) Only items with a po_item, or which are linked to a fund
                #       already, or which belong to invoices which we're trying
                #       to *close* will actually go through this fund_debit
                #       creation process.  In other cases, we'll consider it
                #       ok for an item to remain sans fund_debit for the time
                #       being.

                if (not $U->is_true($item_type->prorate) and
                    ($item->po_item or $item->fund or $invoice->close_date)) {

                    my $debit;
                    if ($item->po_item) {
                        my $po_item = $e->retrieve_acq_po_item($item->po_item)
                            or return $e->die_event;
                        $debit = $e->retrieve_acq_fund_debit($po_item->fund_debit)
                            or return $e->die_event;

                        if ($U->is_true($item_type->blanket)) {
                            # Each payment toward a blanket charge results
                            # in a new debit to track the payment and a 
                            # decrease in the original encumbrance by 
                            # the amount paid on this invoice item
                            $debit->amount($debit->amount - $item->amount_paid);
                            $e->update_acq_fund_debit($debit) or return $e->die_event;
                            $debit = undef; # new debit created below
                        }
                    }

                    if (!$debit) {
                        $debit = Fieldmapper::acq::fund_debit->new;
                        $debit->isnew(1);
                    }

                    return $evt if $evt = _prepare_fund_debit_for_inv_item(
                        $debit, $item, $e, $inv_closing);

                    if ($debit->isnew) {
                        $e->create_acq_fund_debit($debit)
                            or return $e->die_event;
                    } else {
                        $e->update_acq_fund_debit($debit)
                            or return $e->die_event;
                    }

                    $item->fund_debit($debit->id);
                    $e->update_acq_invoice_item($item) or return $e->die_event;
                }
            } elsif ($item->isdeleted) {
                $e->delete_acq_invoice_item($item) or return $e->die_event;

                if ($item->po_item and
                    $e->retrieve_acq_po_item($item->po_item)->fund_debit == $item->fund_debit) {
                    # the debit is attached to the po_item. instead of
                    # deleting it, roll it back to being an encumbrance.
                    # Note: a prorated invoice_item that points to a
                    # po_item could point to a different fund_debit. We
                    # can't go back in time to collect all the prorated
                    # invoice_items (nor is the caller asking us too),
                    # so when that happens, just delete the extraneous
                    # debit (in the else block).
                    my $debit = $e->retrieve_acq_fund_debit($item->fund_debit);
                    if (!$U->us_true($debit->encumbrance)) {
                        $debit->encumbrance('t');
                        $e->update_acq_fund_debit($debit) 
                            or return $e->die_event;
                    }

                } elsif ($item->fund_debit) {

                    my $inv_debit = $e->retrieve_acq_fund_debit($item->fund_debit);

                    if ($U->is_true($item_type->blanket)) {
                        # deleting a payment against a blanket charge means
                        # we have to re-encumber the paid amount by adding
                        # it back to the debit linked to the source po_item.

                        my $po_debit = $e->retrieve_acq_fund_debit($item->po_item->fund_debit);
                        $po_debit->amount($po_debit->amount + $inv_debit->amount);

                        $e->update_acq_fund_debit($po_debit) 
                            or return $e->die_event;
                    }

                    $e->delete_acq_fund_debit($inv_debit) or return $e->die_event;
                }

            } elsif ($item->ischanged) {
                my $debit;

                if (!$item->fund_debit) {
                    # No fund_debit yet? Make one now.
                    $debit = Fieldmapper::acq::fund_debit->new;
                    $debit->isnew(1);

                    return $evt if
                        $evt = _prepare_fund_debit_for_inv_item(
                            $debit, $item, $e, $inv_closing);
                } else {
                    $debit = $e->retrieve_acq_fund_debit($item->fund_debit) or
                        return $e->die_event;
                }

                if ($U->is_true($item_type->blanket)) {
                    # modifying a payment against a blanket charge means
                    # modifying the amount encumbered on the source debit
                    # by the same (but opposite) amount.

                    my $po_debit = $e->retrieve_acq_fund_debit(
                        $item->po_item->fund_debit);

                    my $delta = $debit->amount - $item->amount_paid;
                    $po_debit->amount($po_debit->amount + $delta);
                    $e->update_acq_fund_debit($po_debit) or return $e->die_event;
                }


                $debit->amount($item->amount_paid);
                $debit->fund($item->fund);

                if ($debit->isnew) {
                    # Making a new debit, so make it and link our item to it.
                    $e->create_acq_fund_debit($debit) or return $e->die_event;
                    $item->fund_debit($e->data->id);
                } else {
                    $e->update_acq_fund_debit($debit) or return $e->die_event;
                }

                $e->update_acq_invoice_item($item) or return $e->die_event;
            }
        }
    }

    for my $po_id (@$finalize_pos) {
        my $po = $e->retrieve_acq_purchase_order($po_id) 
            or return $e->die_event;
        
        my $evt = finalize_blanket_po($e, $po);
        return $evt if $evt;
    }

    my $options = {};
    if ($fully_fleshed) {
        $options->{'flesh_provider'} = 1;
        $options->{'flesh_entries'} = 1;
    }
    $invoice = fetch_invoice_impl($e, $invoice->id, $options);

    # entries and items processed above may not represent every item or
    # entry in the invoice.  This will synchronize any remaining debits.
    if ($inv_closing || $inv_reopening) {

        # inv_closing=false implies inv_reopening=true
        $evt = handle_invoice_state_change($e, $invoice, $inv_closing);
        return $evt if $evt;

        $invoice = fetch_invoice_impl($e, $invoice->id, $options);
    }

    # fund limit checks, but only for acq invoice updates in angular
    if ($fund_check) {
        my $updated_fund_summary = amounts_spent_per_fund($e, $invoice->id, $e->authtoken);
        use Data::Dumper;
        $Data::Dumper::Indent = 0;  # No newlines and default indentation
        $Data::Dumper::Terse  = 1;  # No variable names where feasible
        $logger->info("fund check: post, summary = " . Dumper($updated_fund_summary));

        my @stops = (); # funds that hit their stop threshold
        my @warns = (); # funds that hit their warn threshold

        # Loop through each hash in the array
        foreach my $fund_entry (@$updated_fund_summary) {
            # Extract the fund ID and total
            my $fund_id = $fund_entry->{'fund'}->{'id'};
            my $total   = $fund_entry->{'total'};

            $logger->info("fund check: for invoice save, post-business logic: fund $fund_id total $total");

            # Though we have fund data, we need a fieldmapper version for the balance check below
            my $fund = $e->retrieve_acq_fund($fund_id);
            if (!defined $fund) {
                return $e->die_event;
            }

            my $amount_to_test = $total;

            # Test against our fund totals
            my $original_amount = $orig_fund_totals{$fund_id};

            # if there was an original amount, we want to test the difference between old and new
            if ($original_amount) {
                $amount_to_test -= $original_amount;
            }
            my $stop_test = OpenILS::Application::Acq::Order->fund_exceeds_balance_percent_wrapper(
                    $fund, $amount_to_test, $e, 'stop');
            $logger->info("fund check: stop_test = $stop_test");
            if ('1' eq $stop_test) {
                $logger->info("fund check: adding fund to stop list");
                push @stops, { "fund_id" => $fund_id, "fund" => $fund, "amount" => $amount_to_test };
            }
            my $warn_test = OpenILS::Application::Acq::Order->fund_exceeds_balance_percent_wrapper(
                    $fund, $amount_to_test, $e, 'warning');
            $logger->info("fund check: warn_test = $warn_test");
            if ('1' eq $warn_test) {
                $logger->info("fund check: adding fund to warn list");
                push @warns, { "fund_id" => $fund_id, "fund" => $fund, "amount" => $amount_to_test };
            }
        }

        # die on stops unless override
        if (scalar @stops > 0 && !$override) {
            $logger->info("fund check: returning ACQ_FUND_EXCEEDS_STOP_PERCENT");
            return $e->die_event(
                new OpenILS::Event(
                    'ACQ_FUND_EXCEEDS_STOP_PERCENT',
                    "payload" => {
                        "tuples" => \@stops
                    }
                )
            );
        }
        # let's only die on warns during a dry_run
        if (scalar @warns > 0 && !$do_commit) {
            $logger->info("fund check: returning ACQ_FUND_EXCEEDS_WARN_PERCENT");
            return $e->die_event(
                new OpenILS::Event(
                    'ACQ_FUND_EXCEEDS_WARN_PERCENT',
                    "payload" => {
                        "tuples" => \@warns
                    }
                )
            );
        }
    }

    if ($do_commit) {
        $e->commit or return $e->die_event;
    }

    return $invoice;
}

# When an invoice opens or closes, ensure all linked debits match 
# the open/close state of the invoice.
# If $closing is false, code assumes the invoice is reopening.
sub handle_invoice_state_change {
    my ($e, $invoice, $closing) = @_;

    my $enc_find = $closing ? 't' : 'f'; # debits to process
    my $enc_set  = $closing ? 'f' : 't'; # new encumbrance value

    my @debits;
    for my $entry (@{$invoice->entries}) {
        push(@debits, @{find_linked_entry_debits($e, $entry, $enc_find)});
    }

    for my $item (@{$invoice->items}) {
        push(@debits, $item->fund_debit) if
            $item->fund_debit && 
            $item->fund_debit->encumbrance eq $enc_find;
    }

    # udpate all linked debits to match the state of the invoice
    for my $debit (@debits) {
        $debit->encumbrance($enc_set);
        $e->update_acq_fund_debit($debit) or return $e->die_event;
    }

    return undef;
}

sub build_invoice_api {
    my($self, $conn, $auth, $invoice, $entries, $items, $finalize_pos) = @_;

    my $e = new_editor(xact => 1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    if (not ref $invoice) {
        # caller only provided the ID
        $invoice = $e->retrieve_acq_invoice($invoice) or return $e->die_event;
    }

    if (not $invoice->receiver and $invoice->isnew) {
        $invoice->receiver($e->requestor->ws_ou);
    }

    my $context_org = (ref $invoice->receiver) ? $invoice->receiver->id : $invoice->receiver;
    return $e->die_event unless
        $e->allowed('CREATE_INVOICE', $context_org);

    my $dry_run = $self->api_name =~ 'dry_run';
    my $do_commit = !$dry_run;
    my $fleshed = $self->api_name =~ 'fleshed';
    my $override = $self->api_name =~ 'override';
    my $fund_check = $self->api_name =~ 'update.fleshed'; # Dojo ACQ doesn't use this
    $logger->info("fund check: fund_check = $fund_check, api_name = " . $self->api_name);
    return build_invoice_impl($e, $invoice, $entries, $items, $do_commit, $finalize_pos, $fleshed, $override, $fund_check);
}


# 1. set encumbrance=true
# 2. unlink debit entries.
sub rollback_entry_debits {
    my($e, $entry, $orig_entry) = @_;

    # when modifying an entry, roll back all debits that were 
    # affected given the previous state of the entry.
    my $need_count = $orig_entry ? 
        $orig_entry->phys_item_count : $entry->phys_item_count;

    # Un-link all linked debits when rolling back
    my $debits = find_linked_entry_debits($e, $entry);

    # Additionally, find legacy dis-encumbered debits that link 
    # to this entry via lineitem.
    push (@$debits, @{find_non_linked_debits(
        $e, $entry->lineitem, $need_count, undef, 'f')});

    my $lineitem = $e->retrieve_acq_lineitem($entry->lineitem) 
        or return $e->die_event;

    for my $debit (@$debits) {
        # revert to the original estimated amount re-encumber
        $debit->encumbrance('t');
        $debit->amount($lineitem->estimated_unit_price());

        # debit is no longer "invoiced"; detach it from the entry;
        $debit->clear_invoice_entry;

        $e->update_acq_fund_debit($debit) or return $e->die_event;
        update_copy_cost($e, $debit) or return $e->die_event; # clear the cost
    }

    return undef;
}

# invoiced -- debits already linked to this invoice
# inv_closing -- invoice is going from close_date=null to now
# inv_reopening -- invoice is going from close_date=date to null
sub update_entry_debits {
    my($e, $entry, $link_state, $inv_closing, $inv_reopening, $override) = @_;

    my $debits = find_entry_debits(
        $e, $entry, $link_state, $inv_reopening ? 'f' : 't');
    return undef unless @$debits;

    if($entry->phys_item_count > @$debits) {
        if ($override) {
            $logger->info(
                "Overriding ACQ_INVOICE_ENTRY_COUNT_EXCEEDS_DEBITS"
            );
        } else {
            $e->rollback;
            # We can't invoice for more items than we have debits for
            return OpenILS::Event->new(
                'ACQ_INVOICE_ENTRY_COUNT_EXCEEDS_DEBITS', 
                payload => {entry => $entry->id});
        }
    }

    for my $debit (@$debits) {
        my $amount = entry_amount_per_item($entry);
        $debit->amount($amount);
        $debit->encumbrance($inv_closing ? 'f' : 't');

        # debit always reports the invoice_entry responsible
        # for its most recent modification.
        $debit->invoice_entry($entry->id);

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

# This was originally done only for EDI invoices, but needs added to the
# manual invoice-entering process for consistency's sake.
sub uncancel_copies_as_needed {
    my ($e, $entry) = @_;

    return unless $entry->lineitem and $entry->phys_item_count;

    my $li = $e->retrieve_acq_lineitem($entry->lineitem) or
        return $e->die_event;

    # if an invoiced lineitem is marked as cancelled
    # (e.g. back-order), invoicing the lineitem implies
    # we need to un-cancel it

    # collect the LIDs, starting with those that are
    # not cancelled, followed by those that have keep-debits cancel_reasons,
    # followed by non-keep-debit cancel reasons.

    my $lid_ids = $e->json_query({
        select => {acqlid => ['id']},
        from => {
            acqlid => {
                acqcr => {type => 'left'},
                acqfdeb => {type => 'left'}
            }
        },
        where => {
            '+acqlid' => {lineitem => $li->id},
            '+acqfdeb' => {invoice_entry => undef}  # not-yet invoiced copies
        },
        order_by => [{
            class => 'acqcr',
            field => 'keep_debits',
            direction => 'desc'
        }],
        limit => $entry->phys_item_count    # crucial
    });

    for my $lid_id (map {$_->{id}} @$lid_ids) {
        my $lid = $e->retrieve_acq_lineitem_detail($lid_id);
        next unless $lid->cancel_reason;

        $logger->info(
            "un-cancelling invoice lineitem " . $li->id .
            " lineitem_detail " . $lid_id
        );
        $lid->clear_cancel_reason;
        return $e->die_event unless $e->update_acq_lineitem_detail($lid);
    }

    $li->clear_cancel_reason;
    $li->state("on-order") if $li->state eq "cancelled";    # sic
    $li->edit_time("now");

    unless ($e->update_acq_lineitem($li)) {
        my $evt = $e->die_event;
        $logger->error("couldn't clear li cancel reason: ". $evt->{textcode});
        return $evt;
    }

    return;
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

        # XXX It would be nice to have a way to record that a copy was
        # updated by a non-user mechanism, like EDI, but we don't have
        # a clear way to do that here.
        if ($e->requestor) {
            $copy->editor($e->requestor->id);
            $copy->edit_date('now');
        }

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

__PACKAGE__->register_method(
    method => 'invoice_fund_summary',
    api_name    => 'open-ils.acq.invoice.fund_summary',
    signature => {
        desc => q/Gives a breakdown of fund totals for an invoice/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Inv ID/, type => 'number'}
        ],
		return => {desc => q/An array of objects with fund and total keys or an error. Example:
			[
				{
					"fund":{
						"allocations":null,
						"rollover":"f",
						"currency_type":"USD",
						"org":4,
						"summary":null,
						"encumbrance_total":null,
						"spent_balance":null,
						"balance_stop_percent":null,
						"id":4,
						"active":"t",
						"code":"JUV",
						"combined_balance":null,
						"isnew":null,
						"balance_warning_percent":null,
						"ischanged":null,
						"tags":null,
						"isdeleted":null,
						"spent_total":null,
						"propagate":"t",
						"debit_total":null,
						"allocation_total":null,
						"name":"Juvenile",
						"debits":null,
						"year":2023
					},
					"total":"11.00"
				}
			]/
		}
    }
);
sub invoice_fund_summary {
    my ($self, $client, $auth, $inv_id) = @_;
    my $e = new_editor(xact => 1, authtoken=>$auth);
    my $amounts = amounts_spent_per_fund($e, $inv_id, $auth) or
        return $e->die_event;
    $e->rollback;
    return $amounts;
}

# 0 on failure (caller should call $e->die_event), array on success
sub amounts_spent_per_fund {
    my ($e, $inv_id, $auth) = @_;

    $logger->info("fund check: amounts_spent_per_fund for invoice $inv_id");

    my $entries = $e->search_acq_invoice_entry({"invoice" => $inv_id}) || [];
    my $items = $e->search_acq_invoice_item({"invoice" => $inv_id}) || [];
    use Data::Dumper;
    $Data::Dumper::Indent = 0;  # No newlines and default indentation
    $Data::Dumper::Terse  = 1;  # No variable names where feasible
    $logger->info("fund check: amounts_spent_per_fund for invoice $inv_id: entries =" . Dumper($entries));
    $logger->info("fund check: amounts_spent_per_fund for invoice $inv_id: items =" . Dumper($items));
    return 0 unless $entries || $items;

    my %totals_by_fund;
    foreach my $entry (@$entries) {
        my $debits = find_entry_debits($e, $entry, 'linked', "f") or return 0;
        $logger->info("fund check: amounts_spent_per_fund for invoice $inv_id: entry " . $entry->id . " debits = " . Dumper($debits));
        foreach (@$debits) {
            $logger->info("fund check: amounts_spent_per_fund for invoice $inv_id: entry " . $entry->id . " debit = " . Dumper($_));
            $totals_by_fund{$_->fund} ||= 0.0;
            $totals_by_fund{$_->fund} += $_->amount;
        }
    }

    foreach my $item (@$items) {
        next unless $item->fund and $item->amount_paid;
        $logger->info("fund check: amounts_spent_per_fund for invoice $inv_id: item " . $item->id . " fund = " . $item->fund . " paid = " . $item->amount_paid);
        $totals_by_fund{$item->fund} ||= 0.0;
        $totals_by_fund{$item->fund} += $item->amount_paid;
    }

    my @totals = ();
    foreach my $fund_id (keys %totals_by_fund) {
        my $fund;
        if ($auth) { # fleshier behavior with auth
            $fund = $U->simplereq(
                'open-ils.acq',
                'open-ils.acq.fund.retrieve',
                $auth,
                $fund_id,
                { 'flesh_summary' => 1 }
            );
        } else { # original behavior
            $fund = $e->retrieve_acq_fund($fund_id) or return 0;
        }

        push @totals, {
            "fund" => $fund->to_bare_hash,
            "total" => easy_money($totals_by_fund{$fund_id})
        };
    }
    $logger->info("fund check: amounts_spent_per_fund for invoice $inv_id: totals = " . Dumper(\@totals));

    return \@totals;
}

# Returns all debits linked to the provided invoice entry.
# If an encumbrance value is provided, only debits matching the
# encumbrance state are returned.
sub find_linked_entry_debits {
    my($e, $entry, $encumbrance) = @_;

    my $query = {
        select => {acqfdeb => ['id']},
        order_by => {'acqlid' => ['recv_time']},
        from => {acqfdeb => 'acqlid'},
        where => {'+acqfdeb' => {invoice_entry => $entry->id}}
    };

    $query->{where}->{'+acqfdeb'}->{encumbrance} 
        = $encumbrance if $encumbrance;

    my $debits = $e->json_query($query);

    return [] unless @$debits;

    my $debit_ids = [map { $_->{id} } @$debits];
    return $e->search_acq_fund_debit({id => $debit_ids});
}

# Returns all debits for the requested lineitem
# that are not yet linked to an invoice entry.
# If an encumbrance value is provided, only debits matching the
# encumbrance state are returned.
# note: only legacy debits can exist in a state where 
# encumbrance=false and the debit is not linked to an entry.
sub find_non_linked_debits {
    my($e, $li_id, $count, $amount, $encumbrance) = @_;

    my $query = {
        select => {acqfdeb => ['id']},
        order_by => {'acqlid' => ['recv_time']},
        where => {'+acqfdeb' => {invoice_entry => undef}},
        from => {
            acqfdeb => {
                acqlid => {
                    join => {
                        jub => {
                            filter => {id => $li_id}
                        }
                    }
                }
            }
        }
    };

    $query->{where}->{'+acqfdeb'}->{encumbrance} = $encumbrance if $encumbrance;
    $query->{where}->{'+acqfdeb'}->{amount} = $amount if $amount;
    $query->{limit} = $count if defined $count;

    my $debits = $e->json_query($query);

    return [] unless @$debits;

    my $debit_ids = [map { $_->{id} } @$debits];
    return $e->search_acq_fund_debit({id => $debit_ids});
}

# find fund debits related to an invoice entry.
# link_state -- 'linked', 'unlinked', 'all'
# When link_state==undef, start with linked debits, then add unlinked debits.
sub find_entry_debits {
    my($e, $entry, $link_state, $encumbrance, $amount, $count) = @_;

    my $need_count = $count || $entry->phys_item_count;
    my $debits = [];

    if ($link_state eq 'all' || $link_state eq 'linked') {
        $debits = find_linked_entry_debits($e, $entry, $encumbrance);
        return $debits if @$debits && scalar(@$debits) == $need_count;
    }

    # either we don't have enough linked debits to cover the need_count
    # or we are not looking for linked debits.  Keep looking.

    if ($link_state eq 'all' || $link_state eq 'unlinked') {

        # If we found linked debits above, reduce the number of
        # required debits remaining by the number already found.
        $need_count = $need_count - scalar(@$debits);

        push (@$debits, @{find_non_linked_debits(
            $e, $entry->lineitem, $need_count, $amount, $encumbrance)});

    } elsif (scalar(@$debits) == 0) {

        # if a lookup for previously invoiced debits returns zero
        # results, it may be becuase the debits were created before
        # the presence of the acq.fund_debit.invoice_entry column.
        # Fall back to using the old-style lookup.

        push (@$debits, @{find_non_linked_debits(
            $e, $entry->lineitem, $need_count, $amount, $encumbrance)});
    }

    return $debits;
}


__PACKAGE__->register_method(
    method => 'build_invoice_api',
    api_name    => 'open-ils.acq.invoice.retrieve',
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

__PACKAGE__->register_method(
    method => 'build_invoice_api',
    api_name    => 'open-ils.acq.invoice.fleshed.retrieve',
    authoritative => 1,
    signature => {
        desc => q/Creates a new stub invoice (does it really?)/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice Id/, type => 'number'},
        ],
        return => {desc => 'The new invoice w/ entries and items attached, and providers and shippers', type => 'object', class => 'acqinv'}
    }
);

sub fetch_invoice_with_perm_check {
    my($e, $invoice_id, $options) = @_;

    my $invoice = fetch_invoice_impl($e, $invoice_id, $options) or
        return $e->event;
    my $context_org = (ref $invoice->receiver) ? $invoice->receiver->id : $invoice->receiver;
    return $e->event unless $e->allowed(['VIEW_INVOICE', 'CREATE_INVOICE'], $context_org);

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
                "acqinv" => ["entries", "items", "closed_by"],
                "acqii" => ["fund_debit", "purchase_order", "po_item"]
            }
        }
    ];
    if ($options->{"flesh_provider"}) {
        if ($options->{"no_flesh_misc"}) {
            $args = [ $invoice_id, { "flesh" => 1, "flesh_fields" => { "acqinv" => [] } } ];
        }
        push @{ $args->[1]->{flesh_fields}->{acqinv} }, "provider";
        push @{ $args->[1]->{flesh_fields}->{acqinv} }, "shipper";
    }
    if ($options->{"flesh_entries"}) {
        push @{ $args->[1]->{flesh_fields}->{acqie} }, "lineitem";
        push @{ $args->[1]->{flesh_fields}->{jub} }, "lineitem_details";
        push @{ $args->[1]->{flesh_fields}->{acqlid} }, "fund_debit";
    }

    return $e->retrieve_acq_invoice($args);
}

__PACKAGE__->register_method(
    method => 'prorate_invoice',
    api_name    => 'open-ils.acq.invoice.apply_prorate',
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
    my $context_org = (ref $invoice->receiver) ? $invoice->receiver->id : $invoice->receiver;
    return $e->die_event unless $e->allowed('CREATE_INVOICE', $context_org);

    my @lid_debits;
    push(@lid_debits, 
        @{find_entry_debits($e, $_, 'linked', undef, entry_amount_per_item($_))})
        for @{$invoice->entries};

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
            $debit->encumbrance('t'); # Set to 'f' when invoice is closed
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

__PACKAGE__->register_method(
    method => 'finalize_blanket_po_api',
    api_name    => 'open-ils.acq.purchase_order.blanket.finalize',
    signature => {
        desc => q/
            1. Set encumbered amount to zero for all blanket po_item's
            2. If the PO does not have any outstanding lineitems, mark
               the PO as 'received'.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/PO ID/, type => 'number'}
        ],
        return => {desc => '1 on success, event on error'}
    }
);

sub finalize_blanket_po_api {
    my ($self, $client, $auth, $po_id) = @_;

    my $e = new_editor(xact => 1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->die_event;

    return $e->die_event unless
        $e->allowed('CREATE_PURCHASE_ORDER', $po->ordering_agency);

    my $evt = finalize_blanket_po($e, $po);
    return $evt if $evt;

    $e->commit;
    return 1;
}


# 1. set any remaining blanket encumbrances to $0.
# 2. mark the PO as received if there are no pending lineitems.
sub finalize_blanket_po {
    my ($e, $po) = @_;

    my $po_id = $po->id;

    # blanket po_items on this PO
    my $blanket_items = $e->json_query({
        select => {acqpoi => ['id']},
        from => {acqpoi => {aiit => {}}},
        where => {
            '+aiit' => {blanket => 't'},
            '+acqpoi' => {purchase_order => $po_id}
        }
    });

    for my $item_id (map { $_->{id} } @$blanket_items) {

        my $item = $e->retrieve_acq_po_item([
            $item_id, {
                flesh => 1,
                flesh_fields => {acqpoi => ['fund_debit']}
            }
        ]); 

        my $debit = $item->fund_debit or next;

        next if $debit->amount == 0;

        $debit->amount(0);
        $e->update_acq_fund_debit($debit) or return $e->die_event;
    }

    # Number of pending lineitems on this PO. 
    # If there are any, we don't mark 'received'
    my $li_count = $e->json_query({
        select => {jub => [{column => 'id', transform => 'count'}]},
        from => 'jub',
        where => {
            '+jub' => {
                purchase_order => $po_id,
                state => 'on-order'
            }
        }
    })->[0];
    
    if ($li_count->{count} > 0) {
        $logger->info("skipping 'received' state change for po $po_id ".
            "during finalization, because PO has pending lineitems");
        return undef;
    }

    $po->state('received');
    $po->edit_time('now');
    $po->editor($e->requestor->id);

    $e->update_acq_purchase_order($po) or return $e->die_event;

    return undef;
}

1;
