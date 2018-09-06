#!perl
use strict; use warnings;
use Test::More tests => 7;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

diag("Tests ACQ invoices");

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $e = new_editor();
$e->init;

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'
});

ok($script->authtoken, 'Have an authtoken');

my $invoice = Fieldmapper::acq::invoice->new;
$invoice->isnew(1);
$invoice->receiver(1);
$invoice->provider(1);
$invoice->shipper(1);
$invoice->inv_ident(rand());

my $entry = Fieldmapper::acq::invoice_entry->new;
$entry->isnew(1);
$entry->lineitem(3);
$entry->purchase_order(2);
$entry->inv_item_count(1);
$entry->phys_item_count(1);
$entry->cost_billed('25.00');
$entry->actual_cost('25.00');
$entry->amount_paid('25.00');

my $acq_ses = $script->session('open-ils.acq');

my $req = $acq_ses->request(
    'open-ils.acq.invoice.update', $script->authtoken, $invoice, [$entry]);

$invoice = $req->recv->content;
$entry = $invoice->entries->[0];

is(ref $invoice, 'Fieldmapper::acq::invoice', 'Invoice created');

my $inv_debit = 
    $e->search_acq_fund_debit({invoice_entry => $entry->id})->[0];

isnt($inv_debit, undef, 'A fund_debit links to new invoice entry');

is($inv_debit->encumbrance, 't', 
    'Debit is still encumbered after invoice create');

# Close the invoice.  LP#1333254. 
$invoice->close_date('2018-01-01');
$invoice->closed_by(1); # admin
$invoice->ischanged(1);

$req = $acq_ses->request(
    'open-ils.acq.invoice.update', $script->authtoken, $invoice);

$invoice = $req->recv->content;

isnt($invoice->close_date, undef, 'Invoice is closed');

$inv_debit = $e->retrieve_acq_fund_debit($inv_debit->id);

is($inv_debit->encumbrance, 'f', 
    'Debit is disencumbered after invoice close');

# re-open the invoice
$invoice->clear_close_date;
$invoice->clear_closed_by;
$invoice->ischanged(1);

$req = $acq_ses->request(
    'open-ils.acq.invoice.update', $script->authtoken, $invoice);

$invoice = $req->recv->content;

$inv_debit = $e->retrieve_acq_fund_debit($inv_debit->id);

is($inv_debit->encumbrance, 't', 
    'Debit is re-encumbered when invoice is reopened');

