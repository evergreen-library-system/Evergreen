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
        # call only provided the ID
        $invoice = $e->retrieve_acq_invoice($invoice) or return $e->die_event;
    }

    return $e->die_event unless $e->allowed('CREATE_INVOICE', $invoice->receiver);

    if($entries) {
        for my $entry (@$entries) {
            $entry->invoice($invoice->id);
            if($entry->isnew) {
                $e->create_acq_invoice_entry($entry) or return $e->die_event;
            } elsif($entry->isdeleted) {
                $e->delete_acq_invoice_entry($entry) or return $e->die_event;
            } elsif($entry->ischanged) {
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
                $e->delete_acq_invoice_item($item) or return $e->die_event;
            } elsif($item->ischanged) {
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
            where => {'+acqfdeb' => {encumbrance => 't'}}
        });

        next unless @$debits;

        if($entry->phys_item_count > @$debits) {
            $e->rollback;
            # We can't invoice for more items than we have debits for
            return OpenILS::Event->new('ACQ_INVOICE_ENTRY_COUNT_EXCEEDS_DEBITS', payload => {entry => $entry->id});
        }

        for my $debit_id (map { $_->{id} } @$debits) {
            my $debit = $e->retrieve_acq_fund_debit($debit_id);
            $debit->amount($entry->cost_billed);
            $debit->encumbrance('f');
            $e->update_acq_fund_debit($debit) or return $e->die_event;
            $fund_totals{$debit->fund} ||= 0;
            $fund_totals{$debit->fund} += $entry->cost_billed;
        }
    }

    my $total_entry_cost = 0;
    $total_entry_cost += $fund_totals{$_} for keys %fund_totals;

    $logger->info("invoice: total bib cost for invoice = $total_entry_cost");

    # collect amount spent per fund to get percents

    for my $item (@{$invoice->items}) {

        # prorate and create fund debits as appropriate
    }

    $e->rollback;
    return $invoice;

}


1;
