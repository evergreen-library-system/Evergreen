#!perl
use strict; use warnings;
use Test::More tests => 3;
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

my $cancel_reason = $e->retrieve_acq_cancel_reason(1);


subtest("when the lineitem is on order", sub {
    plan tests => 3;
    my $deleteable_line_item_id = $e->json_query({
        select => {jub => ['id']},
        from   => {acqlid => {'jub' => {}} },
        where => {
            '+jub' => {state => 'on-order' }
        }
    })->[0]->{id};
    ok($deleteable_line_item_id, "The test data has sufficient data for our test");

    my $original_lineitem = $e->retrieve_acq_lineitem($deleteable_line_item_id);
    is($original_lineitem->state, "on-order", "Lineitem status begins as on-order");

    my $conn;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);
    OpenILS::Application::Acq::Order::cancel_lineitem($mgr, $deleteable_line_item_id, $cancel_reason);

    my $updated_lineitem = $e->retrieve_acq_lineitem($deleteable_line_item_id);
    is($updated_lineitem->state, "cancelled", "Lineitem status is updated to cancelled");
});

subtest("when the lineitem is backordered", sub {
    plan tests => 3;
    my $deleteable_line_item_id = $e->json_query({
        select => {jub => ['id']},
        from   => {acqlid => {'jub' => {}} },
        where => {
            '+jub' => {cancel_reason => 1283 }
        }
    })->[0]->{id};
    ok($deleteable_line_item_id, "The test data has sufficient data for our test");

    my $original_lineitem = $e->retrieve_acq_lineitem($deleteable_line_item_id);
    is($original_lineitem->cancel_reason, 1283, "Lineitem status begins as backordered");

    my $conn;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);
    OpenILS::Application::Acq::Order::cancel_lineitem($mgr, $deleteable_line_item_id, $cancel_reason);

    my $updated_lineitem = $e->retrieve_acq_lineitem($deleteable_line_item_id);
    is($updated_lineitem->cancel_reason, 1, "Lineitem cancel reason is updated to Invalid ISBN");
});


$e->rollback;
