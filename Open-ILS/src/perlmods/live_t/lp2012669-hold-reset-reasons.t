#!perl
use strict;
use warnings;

use Test::More tests => 23;
diag("Hold Reset Reason Tests");

use OpenILS::Const qw/:const/;
use OpenILS::Utils::TestUtils;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

my $script = OpenILS::Utils::TestUtils->new();
my $U = 'OpenILS::Application::AppUtils';
my $e = new_editor();
use constant {
    BR1_WORKSTATION => 'BR1-test-lp2012669-hold-reset-reasons.t',
    BR1_ID => 4,
    BR2_ID => 5,
    HOLD_ID => 67,
    CANCEL_CAUSE => '5',
    CANCEL_NOTE => 'TEST NOTE',
    REQ_ID => 1,
};

$script->bootstrap;
$e->init;

# Login as admin at BR1.
my $authtoken = $script->authenticate({
    username=>'admin',
    password=>'demo123',
    type=>'staff'
});
ok(
    $script->authtoken,
    'Have an authtoken'
);

# Register workstation.
my $ws = $script->find_or_register_workstation(BR1_WORKSTATION, BR1_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
);

# Logout.
$script->logout();
ok(
    ! $script->authtoken,
    'Successfully logged out'
);

# Login as admin at BR1 using the workstation.
$authtoken = $script->authenticate({
    username=>'admin',
    password=>'demo123',
    type=>'staff',
    workstation => BR1_WORKSTATION
});
ok(
    $script->authtoken,
    'Have an authtoken'
);

# == Reseting Concerto hold 67.

$U->simplereq(
    'open-ils.circ',
    'open-ils.circ.hold.reset',
    $authtoken,
    HOLD_ID
);

my $ahrrre = $e->search_action_hold_request_reset_reason_entry([{hold => HOLD_ID},{order_by =>[{class => 'ahrrre', field=> 'reset_time', direction => 'DESC'}]}])->[0];
is($ahrrre->reset_reason, OILS_HOLD_MANUAL_RESET,"manual reset code applied to reset reason");
is($ahrrre->requestor, REQ_ID,"requestor ID applied to reset reason");
is($ahrrre->requestor_workstation, $ws,"workstation applied to reset reason");

$U->simplereq(
    'open-ils.circ',
    'open-ils.circ.hold.cancel',
    $authtoken,
    HOLD_ID,
    CANCEL_CAUSE
);

$ahrrre = $e->search_action_hold_request_reset_reason_entry([{hold => HOLD_ID},{order_by =>[{class => 'ahrrre', field=> 'reset_time', direction => 'DESC'}]}])->[0];
is($ahrrre->reset_reason, OILS_HOLD_CANCELED,"cancel code applied to reset reason");
is($ahrrre->requestor, REQ_ID,"requestor ID applied to reset reason");
is($ahrrre->requestor_workstation, $ws,"workstation applied to reset reason");
is($ahrrre->note, "Cancel Cause: Staff forced","cancel cause appended to reset reason's note");

$U->simplereq(
    'open-ils.circ',
    'open-ils.circ.hold.uncancel',
    $authtoken,
    HOLD_ID
);

$ahrrre = $e->search_action_hold_request_reset_reason_entry([{hold => HOLD_ID},{order_by =>[{class => 'ahrrre', field=> 'reset_time', direction => 'DESC'}]}])->[0];
is($ahrrre->reset_reason, OILS_HOLD_UNCANCELED,"cancel code applied to reset reason");
is($ahrrre->requestor, REQ_ID,"requestor ID applied to reset reason");
is($ahrrre->requestor_workstation, $ws,"workstation applied to reset reason");

$U->simplereq(
    'open-ils.circ',
    'open-ils.circ.hold.update',
    $authtoken,
    undef,
    {id => HOLD_ID, frozen => 1}
);

$ahrrre = $e->search_action_hold_request_reset_reason_entry([{hold => HOLD_ID},{order_by =>[{class => 'ahrrre', field=> 'reset_time', direction => 'DESC'}]}])->[0];
is($ahrrre->reset_reason, OILS_HOLD_FROZEN,"frozen code applied to reset reason");
is($ahrrre->requestor, REQ_ID,"requestor ID applied to reset reason");
is($ahrrre->requestor_workstation, $ws,"workstation applied to reset reason");

$U->simplereq(
    'open-ils.circ',
    'open-ils.circ.hold.update',
    $authtoken,
    undef,
    {id => HOLD_ID, frozen => 0}
);

$ahrrre = $e->search_action_hold_request_reset_reason_entry([{hold => HOLD_ID},{order_by =>[{class => 'ahrrre', field=> 'reset_time', direction => 'DESC'}]}])->[0];
is($ahrrre->reset_reason, OILS_HOLD_UNFROZEN,"unfrozen code applied to reset reason");
is($ahrrre->requestor, REQ_ID,"requestor ID applied to reset reason");
is($ahrrre->requestor_workstation, $ws,"workstation applied to reset reason");

$U->simplereq(
    'open-ils.circ',
    'open-ils.circ.hold.update',
    $authtoken,
    undef,
    {id => HOLD_ID, pickup_lib => BR2_ID}
);

$ahrrre = $e->search_action_hold_request_reset_reason_entry([{hold => HOLD_ID},{order_by =>[{class => 'ahrrre', field=> 'reset_time', direction => 'DESC'}]}])->[0];
is($ahrrre->reset_reason, OILS_HOLD_UPDATED,"hold updated code applied to reset reason");
is($ahrrre->requestor, REQ_ID,"requestor ID applied to reset reason");
is($ahrrre->requestor_workstation, $ws,"workstation applied to reset reason");

$U->simplereq(
    'open-ils.circ',
    'open-ils.circ.hold.update',
    $authtoken,
    undef,
    {id => HOLD_ID, pickup_lib => BR1_ID}
);

my $ahrrre_list = $e->search_action_hold_request_reset_reason_entry([{hold => HOLD_ID},{order_by =>[{class => 'ahrrre', field=> 'reset_time', direction => 'DESC'}]}]);

#clean up all reset reasons
$e->xact_begin;
if ($ahrrre_list) {
    for my $rr (@$ahrrre_list) {
        next unless $rr;
        $e->delete_action_hold_request_reset_reason_entry($rr);
    }
}
$e->xact_commit;