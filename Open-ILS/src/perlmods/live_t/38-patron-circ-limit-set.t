#!perl

use strict; use warnings;

use Test::More tests => 3;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Penalty;

diag('Test circ limit sets');

use constant WORKSTATION_NAME => 'BR4-test-38-patron-max-items.t';
use constant WORKSTATION_LIB => 7; # BR4
use constant BR4_PATRON_ID => 79; # Shawn Barber
use constant FIRST_ITEM_BARCODE => 'CONC71000338';
use constant SECOND_ITEM_BARCODE => 'FRE700001428';
use constant THIRD_ITEM_BARCODE => 'RDA710001690';
use constant CCLS_ID => 9999;
use constant CCMLSM_ID => 6789;
use constant CCLSACPL_ID => 5678;
use constant SHELVING_LOCATION_ID => 124; # Science Fiction at BR4

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;
my $e = new_editor(xact => 1);
$e->init;

my $ccls = Fieldmapper::config::circ_limit_set->new;
$ccls->items_out(1);
$ccls->name(WORKSTATION_NAME);
$ccls->owning_lib(WORKSTATION_LIB);
$ccls->id(CCLS_ID);

my $ccmlsm = Fieldmapper::config::circ_matrix_limit_set_map->new;
$ccmlsm->active(1);
$ccmlsm->limit_set(CCLS_ID);
$ccmlsm->matchpoint(1);
$ccmlsm->id(CCMLSM_ID);

my $cclsacpl = Fieldmapper::config::circ_limit_set_copy_loc_map->new;
$cclsacpl->limit_set(CCLS_ID);
$cclsacpl->copy_loc(SHELVING_LOCATION_ID);
$cclsacpl->id(CCLSACPL_ID);

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
    $script->logout();

    # Login again with the workstation
    my $credentials = {
        username => 'admin',
        password => 'demo123',
        type => 'staff',
        workstation => WORKSTATION_NAME
    };
    $script->authenticate($credentials);
    ok(
        $script->authtoken,
        'Successfully authenticated with the new workstation'
    );
    # Checkout two items to the patron
    $script->do_checkout({
        patron => BR4_PATRON_ID,
        barcode => FIRST_ITEM_BARCODE});
    $script->do_checkout({
        patron => BR4_PATRON_ID,
        barcode => SECOND_ITEM_BARCODE});

    # Add a circ limit set that only allows 1 item to be checked out
    $e->xact_begin;
    $e->create_config_circ_limit_set($ccls);
    $e->create_config_circ_matrix_limit_set_map($ccmlsm);
    $e->create_config_circ_limit_set_copy_loc_map($cclsacpl);
    $e->xact_commit;
});

subtest('Checkout item past max items', sub {
    plan tests => 1;
    my $checkout_resp = $script->do_checkout({
        patron => BR4_PATRON_ID,
        barcode => THIRD_ITEM_BARCODE});
    is(
        $checkout_resp->{textcode},
        'PATRON_EXCEEDS_CHECKOUT_COUNT',
        'Checkout returned a PATRON_EXCEEDS_CHECKOUT_COUNT event'
    );
});

subtest('Cleanup', sub {
    plan tests => 5;
    # Check in the items
    $script->do_checkin({barcode => FIRST_ITEM_BARCODE});
    $script->do_checkin({barcode => SECOND_ITEM_BARCODE});

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

    # Delete circ configuration that this test created previously
    $e->xact_begin;
    $e->delete_config_circ_limit_set_copy_loc_map($cclsacpl);
    $e->delete_config_circ_matrix_limit_set_map($ccmlsm);
    $e->delete_config_circ_limit_set($ccls);
    $e->xact_commit;

    my $results = $e->search_config_circ_limit_set_copy_loc_map({id => CCLSACPL_ID});
    is(scalar(@{ $results }), 0, 'Successfully deleted circ limit set copy loc map');
    $results = $e->search_config_circ_matrix_limit_set_map({id => CCMLSM_ID});
    is(scalar(@{ $results }), 0, 'Successfully deleted circ matrix limit set map');
    $results = $e->search_config_circ_limit_set({id => CCLS_ID});
    is(scalar(@{ $results }), 0, 'Successfully deleted circ limit set');
    $script->logout();
});

