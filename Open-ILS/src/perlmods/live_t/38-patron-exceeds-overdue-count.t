#!perl

use strict; use warnings;

use Test::More tests => 3;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Penalty;

diag('Test the PATRON_EXCEEDS_OVERDUE_COUNT threshold');

use constant WORKSTATION_NAME => 'BR4-test-38-patron-exceeds-overdue-count.t';
use constant WORKSTATION_LIB => 7; # BR4
use constant BR4_PATRON_ID => 7; # Brittany Walker, patron with overdues
use constant ITEM_BARCODE => 'RDA710001690';
use constant ORIGINAL_THRESHOLD => 10.0;

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;
my $e = new_editor(xact => 1);
$e->init;

my $pgpt = $e->search_permission_grp_penalty_threshold({penalty => 2})->[0];

subtest('Setup', sub {
    plan tests => 3;
    $script->authenticate({
        username => 'admin',
        password => 'demo123',
        type => 'staff'
    });
    ok(
        $script->authtoken,
        'Have an authtoken'
    );

    # Register a workstation
    my $ws = $script->register_workstation(WORKSTATION_NAME,WORKSTATION_LIB);
    ok(
        ! ref $ws,
        'Registered a new workstation'
    );
    # Login again, this time with the appropriate workstation
    my $credentials = {
        username => 'admin',
        password => 'demo123',
        type => 'staff',
        workstation => WORKSTATION_NAME
    };
    $script->authenticate($credentials);
    ok(
        $script->authtoken,
        'Have an authtoken for the approprate workstation'
    );

    # Set the threshold to 1
    $pgpt->threshold(1.0);
    $e->xact_begin;
    $e->update_permission_grp_penalty_threshold($pgpt);

    # Make sure that the patron account is not expired
    my $patron = $e->retrieve_actor_user(BR4_PATRON_ID);
    $patron->expire_date(DateTime->today()->add( days => 7 )->iso8601());
    $e->update_actor_user($patron);
    $e->xact_commit;
});

subtest('Attempt to checkout another item', sub {
    plan tests => 4;
    my $penalties_on_account = $e->search_actor_user_standing_penalty({usr => BR4_PATRON_ID});
    is(
        scalar @{ $penalties_on_account },
        0,
        'Patron starts without any penalties'
    );
    my $checkout_resp = $script->do_checkout({
        patron => BR4_PATRON_ID,
        barcode => ITEM_BARCODE});
    is(
        $checkout_resp->{textcode},
        'PATRON_EXCEEDS_OVERDUE_COUNT',
        'Attempted checkout returned a PATRON_EXCEEDS_OVERDUE_COUNT event'
    );
        # Search for new penalties on the patron account
    $penalties_on_account = $e->search_actor_user_standing_penalty({usr => BR4_PATRON_ID});
    is(
        scalar @{ $penalties_on_account },
        1,
        'Patron received a new penalty'
    );
    is(
        $penalties_on_account->[0]->standing_penalty,
        2,
        'Patron received the PATRON_EXCEEDS_OVERDUE_COUNT penalty'
    );
});

subtest('Cleanup', sub {
    plan tests => 2;
    # Check in the item
    $script->do_checkin({barcode => ITEM_BARCODE});

    # Set the threshold back to 10
    $pgpt->threshold(ORIGINAL_THRESHOLD);
    $e->xact_begin;
    $e->update_permission_grp_penalty_threshold($pgpt);
    $e->xact_commit;

    # Recalculate the penalties
    $e->xact_begin;
    OpenILS::Utils::Penalty->calculate_penalties($e, BR4_PATRON_ID, WORKSTATION_LIB);
    $e->xact_commit;
    my $penalties = $e->search_actor_user_standing_penalty({usr => BR4_PATRON_ID});
    is(scalar(@{ $penalties }), 0, 'Successfully removed penalties from user account');

    # Delete workstations that this test created previously
    my $workstations = $e->search_actor_workstation({name => WORKSTATION_NAME});
    $e->xact_begin;
    for my $workstation (@{$workstations}) {
        $e->delete_actor_workstation($workstation) or return $e->die_event;
    }
    $e->xact_commit;
    ok(
        ! $script->find_workstation(WORKSTATION_NAME,WORKSTATION_LIB),
        'Deleted the workstation'
    );
});

