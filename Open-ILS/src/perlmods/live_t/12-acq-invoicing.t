#!perl
use strict; use warnings;
use Test::More tests => 4;
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
$invoice->complete('f');

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

is(ref $invoice, 'Fieldmapper::acq::invoice', 'Invoice created');

# Close the invoice.  LP#1333254. 
$invoice->complete('t');
$invoice->ischanged(1);

$req = $acq_ses->request(
    'open-ils.acq.invoice.update', $script->authtoken, $invoice);

$invoice = $req->recv->content;

is($invoice->complete, 't', 'Invoice is closed');

$entry = $invoice->entries->[0];
my $debits = $e->search_acq_fund_debit({id => [1,2]});
my @matching = grep { ($_->invoice_entry || '') eq $entry->id } @$debits;

isnt(scalar(@matching), 0, 
    'At least one fund_debit should link to new invoice entry');

