#!perl
use strict; use warnings;
use Test::More tests => 11;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::Acq::Order;

diag("Tests ACQ purchase orders");

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'
});

my $e = $script->editor(authtoken=>$script->authtoken);
$e->xact_begin;

ok($script->authtoken, 'Have an authtoken');

my $conn; # dummy for now
my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

my $origpo = $e->retrieve_acq_purchase_order(2);
is($origpo->state, 'on-order', 'order starts at expected state') or
    BAIL_OUT('order 2 does not have expected state');

my $origli3 = $e->retrieve_acq_lineitem(3);
my $origli4 = $e->retrieve_acq_lineitem(4);
my $origli5 = $e->retrieve_acq_lineitem(5);

is($origli3->state, 'on-order', 'line item 3 starts at expected state') or
    BAIL_OUT('line item 3 does not have expected state');
is($origli4->state, 'cancelled', 'line item 4 starts at expected state') or
    BAIL_OUT('line item 4 does not have expected state');
is($origli5->state, 'cancelled', 'line item 5 starts at expected state') or
    BAIL_OUT('line item 5 does not have expected state');
is($origli4->cancel_reason, 1283, 'line item 4 starts at expected cancel_reason') or
    BAIL_OUT('line item 4 does not have expected cancel_reason');
is($origli5->cancel_reason, 1, 'line item 5 starts at expected cancel_reason') or
    BAIL_OUT('line item 5 does not have expected cancel_reason');

my $ret = OpenILS::Application::Acq::Order::check_purchase_order_received($mgr, 2);
is($ret->state, 'on-order', 'order cannot be received (yet)');

OpenILS::Application::Acq::Order::receive_lineitem($mgr, 3, 1);
my $li = $e->retrieve_acq_lineitem(3);
is($li->state, 'received', 'line item 3 received');

$ret = OpenILS::Application::Acq::Order::check_purchase_order_received($mgr, 2);
is($ret->state, 'on-order', 'order still cannot be received');

$li = $e->retrieve_acq_lineitem(4);
$li->cancel_reason(2); # this one has keep_debits = false, i.e., we don't expect
                       # this one to ever show up
$e->update_acq_lineitem($li);

$ret = OpenILS::Application::Acq::Order::check_purchase_order_received($mgr, 2);
is($ret->state, 'received', 'LP#1257915: order now received');

$e->rollback;
