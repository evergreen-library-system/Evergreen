#!perl

use Test::More tests => 12;

diag("Test checking for, creating, and restricting patron opt-in.");

use constant WORKSTATION_NAME => 'BR1-test-12-lp1533329-opt-in.t';
use constant WORKSTATION_LIB => 4; # BR1, a branch of SYS1
use constant PATRON_LIB => 6; # BR3, a branch of SYS2
use constant PATRON_SYS => 3; # SYS2
use constant SYS_DEPTH => 1; # depth of "System" org type
use constant PATRON_BARCODE => '99999359616';

use strict; use warnings;

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

our $U = "OpenILS::Application::AppUtils";

my $e = new_editor(xact => 1);
$e->init;

# initialize a new aous object for insertion into the db
sub new_org_setting {
    my ($org_unit, $name, $value) = @_;
    my $set = Fieldmapper::actor::org_unit_setting->new();
    $set->org_unit($org_unit);
    $set->name($name);
    $set->value($value);
    return $set;
}

sub opt_in_enabled {
    my $resp = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.org_unit_opt_in.enabled'
    );
    return $resp;
}

# do an opt-in check
sub opt_in_check {
    my ($authtoken, $usr_id) = @_;
    my $resp = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.org_unit_opt_in.check',
        $authtoken, $usr_id);
    return $resp;
}

SKIP: {
    skip 'cannot test opt-in unless enabled in opensrf.xml', 12 unless(opt_in_enabled());

    #----------------------------------------------------------------
    # 1. Login, register workstation, get authtoken.
    #----------------------------------------------------------------
    $script->authenticate({
        username => 'admin',
        password => 'demo123',
        type => 'staff'});
    ok(
        $script->authtoken,
        'Have an authtoken'
    );
    my $ws = $script->register_workstation(WORKSTATION_NAME,WORKSTATION_LIB);
    ok(
        ! ref $ws,
        'Registered a new workstation'
    );
    $script->logout();
    $script->authenticate({
        username => 'admin',
        password => 'demo123',
        type => 'staff',
        workstation => WORKSTATION_NAME});
    ok(
        $script->authtoken,
        'Have an authtoken associated with the workstation'
    );

    #----------------------------------------------------------------
    # 2. Set org.patron_opt_boundary for SYS2, so that BR1 is outside
    # the boundary.
    #----------------------------------------------------------------
    $e->xact_begin;
    my $boundary = new_org_setting(PATRON_SYS, 'org.patron_opt_boundary', SYS_DEPTH);
    my $boundary_stat = $e->create_actor_org_unit_setting($boundary);
    ok($boundary_stat, 'Opt boundary setting created successfully');
    $e->xact_commit;

    #----------------------------------------------------------------
    # 3. Check opt-in for test patron.  It should return 0.
    #----------------------------------------------------------------
    my $patron = $U->fetch_user_by_barcode(PATRON_BARCODE);
    is(
        opt_in_check($script->authtoken, $patron->id),
        '0',
        'Opt-in check for non-opted-in patron correctly returned 0'
    );

    #----------------------------------------------------------------
    # 4. Set org.restrict_opt_to_depth at SYS2, so that BR1 is
    # outside SYS2's section of the tree at the specified depth (thus
    # preventing opt-in).
    #----------------------------------------------------------------
    $e->xact_begin;
    my $restrict = new_org_setting(PATRON_SYS, 'org.restrict_opt_to_depth', SYS_DEPTH);
    my $restrict_stat = $e->create_actor_org_unit_setting($restrict);
    ok($restrict_stat, 'Opt restrict depth setting created successfully');
    $e->xact_commit;

    #----------------------------------------------------------------
    # 5. Check opt-in for test patron.  It should return 2.
    #----------------------------------------------------------------
    is(
        opt_in_check($script->authtoken, $patron->id),
        '2',
        'Opt-in check for patron at restricted opt-in library correctly returned 2'
    );

    #----------------------------------------------------------------
    # 6. Remove the org.restrict_opt_to_depth setting for SYS2.
    #----------------------------------------------------------------
    $e->xact_begin;
    my $delete_restrict_stat = $e->delete_actor_org_unit_setting($restrict);
    ok($delete_restrict_stat, 'Opt restrict depth setting deleted successfully');
    $e->xact_commit;

    #----------------------------------------------------------------
    # 7. Create opt-in for test patron.
    #----------------------------------------------------------------
    my $opt_id = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.org_unit_opt_in.create',
        $script->authtoken, $patron->id, WORKSTATION_LIB);
    ok($opt_id, 'Patron successfully opted in');

    #----------------------------------------------------------------
    # 8. Check opt-in for test patron.  It should return 1.
    #----------------------------------------------------------------
    is(
        opt_in_check($script->authtoken, $patron->id),
        '1',
        'Opt-in check for opted-in patron correctly returned 1'
    );

    #----------------------------------------------------------------
    # 9. Delete opt-in.
    #----------------------------------------------------------------
    my $opt = $U->simplereq(
        'open-ils.cstore',
        'open-ils.cstore.direct.actor.usr_org_unit_opt_in.retrieve',
        $opt_id
    );
    $e->xact_begin;
    my $delete_opt_stat = $e->delete_actor_usr_org_unit_opt_in($opt);
    ok($delete_opt_stat, 'Opt-in deleted successfully');
    $e->xact_commit;

    #----------------------------------------------------------------
    # 10. Remove opt boundary setting.
    #----------------------------------------------------------------
    $e->xact_begin;
    my $delete_setting_stat = $e->delete_actor_org_unit_setting($boundary);
    ok($delete_setting_stat, 'Opt boundary setting deleted successfully');
    $e->xact_commit;
}

