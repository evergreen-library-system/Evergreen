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
	api_name	=> 'open-ils.acq.invoice.create',
	signature => {
        desc => q/Creates a new stub invoice/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice Object/, type => 'object', class => 'acqinv'},
        ],
        return => {desc => 'The new invoice w/ entries and items attached', type => 'object', class => 'acqinv'}
    }
);

__PACKAGE__->register_method(
	method => 'build_invoice_api',
	api_name	=> 'open-ils.acq.invoice.attach',
	signature => {
        desc => q/Attach invoice entries and invoice items to an existing invoice/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Invoice ID/, type => 'number'},
            {desc => q/Entries/, type => 'array'},
            {desc => q/Items/, type => 'array'},
        ],
        return => {desc => 'The invoice w/ entries and items attached', type => 'object', class => 'acqinv'}
    }
);

sub build_invoice_api {
    my($self, $conn, $auth, $invoice, $entries, $items) = @_;

    my $e = new_editor(xact => 1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;


    if($self->api_name =~ /create/) {
        $invoice->receiver($e->requestor->ws_ou) unless $invoice->receiver;
        $invoice->recv_method('PPR') unless $invoice->recv_method;
        $invoice->recv_date('now') unless $invoice->recv_date;
        $e->create_acq_invoice($invoice) or return $e->die_event;
    } else {
        $invoice = $e->retrieve_acq_invoice($invoice) or return $e->die_event;
    }

    return $e->die_event unless $e->allowed('CREATE_INVOICE', $invoice->receiver);

    if($entries) {
        for my $entry (@$entries) {
            $entry->invoice($invoice->id);
            $e->create_acq_invoice_entry($entry) or return $e->die_event;
        }
    }

    if($items) {
        for my $item (@$items) {
            $item->invoice($invoice->id);
            $e->create_acq_invoice_item($item) or return $e->die_event;
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
            "flesh" => 4,
            "flesh_fields" => {
                "acqinv" => ["entries", "items"],
                "acqie" => ["lineitem", "purchase_order"],
                "acqii" => ["fund_debit"],
                "jub" => ["attributes"]
            }
        }
    ];
    return $e->retrieve_acq_invoice($args);
}


1;
