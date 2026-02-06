#!perl
use strict; use warnings;
use Test::More;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);
use OpenSRF::Utils::JSON;

my $script = OpenILS::Utils::TestUtils->new();
my $U = 'OpenILS::Application::AppUtils';

diag('Test LP 1861239 Aged Hold & Circ Anonymization Settings');

use constant {
    BR1_ID => 4,
    BR2_ID => 5,
    BM1_ID => 9,
    BR4_ID => 7,
    BR1_PATRONID => 16,
    BR2_PATRONID => 15,
    BM1_PATRONID => 18,
    BR4_PATRONID => 10,
    STAFF_USER => 'admin',
    STAFF_PASSWD => 'demo123'
};

my $credentials = {
    username => STAFF_USER,
    password => STAFF_PASSWD,
    type => 'staff'
};

# Log in as staff.
my $authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    'Logged in'
) or BAIL_OUT('Must log in');

# Do BR4, first:
my $workstation = 'BR4-LP1861239-test';
my $ws = $script->find_or_register_workstation($workstation, BR4_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
) or BAIL_OUT('Need workstation');

# Have to logout before we can use the workstation.
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# Login with the workstation
$credentials->{workstation} = $workstation;
$credentials->{password} = STAFF_PASSWD;
$authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    "Logged in with workstation: $workstation"
);

# Set the relevant settings
my $rv = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $authtoken,
    BR4_ID,
    {
        'circ.do_not_retain_year_of_birth_on_aged' => OpenSRF::Utils::JSON->true,
        'circ.do_not_retain_post_code_on_aged' => OpenSRF::Utils::JSON->true,
        'holds.do_not_retain_year_of_birth_on_aged' => OpenSRF::Utils::JSON->true,
        'holds.do_not_retain_post_code_on_aged' => OpenSRF::Utils::JSON->true
    }
);
is(
    $rv,
    1,
    'Org. Unit Setttings update'
);

# Get our patron for BR4:
my $patron = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.retrieve',
    $authtoken,
    BR4_PATRONID
);
isa_ok(
    ref $patron,
    'Fieldmapper::actor::user',
    'Got patron for BR4'
);

# Get our patron's circulations
my $circs = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.circulation.search.atomic',
    {usr => $patron->id, checkin_time => undef}
);
ok(
    ref $circs && @{$circs},
    'Got open circulations for BR4 patron'
);

# Check them in with noop and "amnesty mode."
my $checkin_opts = {
    override_args => {all => 1},
    noop => 1,
    void_overdues => 1
};
for my $circ (@{$circs}) {
    $checkin_opts->{copy_id} = $circ->target_copy;
    my $r = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.checkin.override',
        $authtoken,
        $checkin_opts
    );
}

# Find the patron's holds
my $holds = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.hold_request.search.atomic',
    {usr => $patron->id}
);
ok(
    ref $holds && @{$holds},
    'Got holds for BR4 patron'
);

# Delete the patron to instantly archive the circs and holds
$rv = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.delete',
    $authtoken,
    $patron->id,
    undef
);
is(
    $rv,
    1,
    'Patron is deleted'
);

# Check aged circs and aged holds:
my @circ_ids = map {$_->id} @{$circs};
my @hold_ids = map {$_->id} @{$holds};
my $aged_circs = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.aged_circulation.search.atomic',
    {id => [@circ_ids], usr_post_code => undef, usr_birth_year => undef}
);
is(
    scalar(@{$aged_circs}),
    scalar(@{$circs}),
    'Got correct number of aged circs'
);
my $aged_holds = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.aged_hold_request.search.atomic',
    {id => [@hold_ids], usr_post_code => undef, usr_birth_year => undef}
);
is(
    scalar(@{$aged_holds}),
    scalar(@{$holds}),
    'Got correct number of aged holds'
);

# Logout so we can test at other branches
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# --------------------

# Log in as staff.
delete $credentials->{workstation};
$credentials->{password} = STAFF_PASSWD;
$authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    'Logged in'
) or BAIL_OUT('Must log in');

# Test keeping only post code at  BR2:
$workstation = 'BR2-LP1861239-test';
$ws = $script->find_or_register_workstation($workstation, BR2_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
) or BAIL_OUT('Need workstation');

# Have to logout before we can use the workstation.
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# Login with the workstation
$credentials->{workstation} = $workstation;
$credentials->{password} = STAFF_PASSWD;
$authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    "Logged in with workstation: $workstation"
);

# Set the relevant settings
$rv = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $authtoken,
    BR2_ID,
    {
        'circ.do_not_retain_year_of_birth_on_aged' => OpenSRF::Utils::JSON->true,
        'holds.do_not_retain_year_of_birth_on_aged' => OpenSRF::Utils::JSON->true,
    }
);
is(
    $rv,
    1,
    'Org. Unit Setttings update'
);

# Get our patron for BR2:
$patron = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.retrieve',
    $authtoken,
    BR2_PATRONID
);
isa_ok(
    ref $patron,
    'Fieldmapper::actor::user',
    'Got patron for BR2'
);

# Get our patron's circulations
$circs = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.circulation.search.atomic',
    {usr => $patron->id, checkin_time => undef}
);
ok(
    ref $circs && @{$circs},
    'Got open circulations for BR2 patron'
);

# Check them in with noop and "amnesty mode."
$checkin_opts = {
    override_args => {all => 1},
    noop => 1,
    void_overdues => 1
};
for my $circ (@{$circs}) {
    $checkin_opts->{copy_id} = $circ->target_copy;
    my $r = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.checkin.override',
        $authtoken,
        $checkin_opts
    );
}

# Find the patron's holds
$holds = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.hold_request.search.atomic',
    {usr => $patron->id}
);
ok(
    ref $holds && @{$holds},
    'Got holds for BR2 patron'
);

# Delete the patron to instantly archive the circs and holds
$rv = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.delete',
    $authtoken,
    $patron->id,
    undef
);
is(
    $rv,
    1,
    'Patron is deleted'
);

# Check aged circs and aged holds:
@circ_ids = map {$_->id} @{$circs};
@hold_ids = map {$_->id} @{$holds};
$aged_circs = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.aged_circulation.search.atomic',
    {id => [@circ_ids], usr_post_code => {'<>' => undef}, usr_birth_year => undef}
);
is(
    scalar(@{$aged_circs}),
    scalar(@{$circs}),
    'Got correct number of aged circs'
);
$aged_holds = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.aged_hold_request.search.atomic',
    {id => [@hold_ids], usr_post_code => {'<>' => undef}, usr_birth_year => undef}
);
is(
    scalar(@{$aged_holds}),
    scalar(@{$holds}),
    'Got correct number of aged holds'
);

# Logout so we can test at other branches
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# --------------------

# Log in as staff.
delete $credentials->{workstation};
$credentials->{password} = STAFF_PASSWD;
$authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    'Logged in'
) or BAIL_OUT('Must log in');

# Keep birth year only at  BM1
$workstation = 'BM1-LP1861239-test';
$ws = $script->find_or_register_workstation($workstation, BM1_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
) or BAIL_OUT('Need workstation');

# Have to logout before we can use the workstation.
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# Login with the workstation
$credentials->{workstation} = $workstation;
$credentials->{password} = STAFF_PASSWD;
$authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    "Logged in with workstation: $workstation"
);

# Set the relevant settings
$rv = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $authtoken,
    BM1_ID,
    {
        'circ.do_not_retain_post_code_on_aged' => OpenSRF::Utils::JSON->true,
        'holds.do_not_retain_post_code_on_aged' => OpenSRF::Utils::JSON->true
    }
);
is(
    $rv,
    1,
    'Org. Unit Setttings update'
);

# Get our patron for BM1:
$patron = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.retrieve',
    $authtoken,
    BM1_PATRONID
);
isa_ok(
    ref $patron,
    'Fieldmapper::actor::user',
    'Got patron for BM1'
);

# Get our patron's circulations
$circs = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.circulation.search.atomic',
    {usr => $patron->id, checkin_time => undef}
);
ok(
    ref $circs && @{$circs},
    'Got open circulations for BM1 patron'
);

# Check them in with noop and "amnesty mode."
$checkin_opts = {
    override_args => {all => 1},
    noop => 1,
    void_overdues => 1
};
for my $circ (@{$circs}) {
    $checkin_opts->{copy_id} = $circ->target_copy;
    my $r = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.checkin.override',
        $authtoken,
        $checkin_opts
    );
}

# Find the patron's holds
$holds = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.hold_request.search.atomic',
    {usr => $patron->id}
);
ok(
    ref $holds && @{$holds},
    'Got holds for BM1 patron'
);

# Delete the patron to instantly archive the circs and holds
$rv = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.delete',
    $authtoken,
    $patron->id,
    undef
);
is(
    $rv,
    1,
    'Patron is deleted'
);

# Check aged circs and aged holds:
@circ_ids = map {$_->id} @{$circs};
@hold_ids = map {$_->id} @{$holds};
$aged_circs = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.aged_circulation.search.atomic',
    {id => [@circ_ids], usr_post_code => undef, usr_birth_year => {'<>' => undef}}
);
is(
    scalar(@{$aged_circs}),
    scalar(@{$circs}),
    'Got correct number of aged circs'
);
$aged_holds = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.aged_hold_request.search.atomic',
    {id => [@hold_ids], usr_post_code => undef, usr_birth_year => {'<>' => undef}}
);
is(
    scalar(@{$aged_holds}),
    scalar(@{$holds}),
    'Got correct number of aged holds'
);

# Logout so we can test at other branches
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# --------------------

# Log in as staff.
delete $credentials->{workstation};
$credentials->{password} = STAFF_PASSWD;
$authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    'Logged in'
) or BAIL_OUT('Must log in');

# Do BR1 Without any settings
$workstation = 'BR1-LP1861239-test';
$ws = $script->find_or_register_workstation($workstation, BR1_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
) or BAIL_OUT('Need workstation');

# Have to logout before we can use the workstation.
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# Login with the workstation
$credentials->{workstation} = $workstation;
$credentials->{password} = STAFF_PASSWD;
$authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    "Logged in with workstation: $workstation"
);

# Get our patron for BR1:
$patron = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.retrieve',
    $authtoken,
    BR1_PATRONID
);
isa_ok(
    ref $patron,
    'Fieldmapper::actor::user',
    'Got patron for BR1'
);

# Get our patron's circulations
$circs = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.circulation.search.atomic',
    {usr => $patron->id, checkin_time => undef}
);
ok(
    ref $circs && @{$circs},
    'Got open circulations for BR1 patron'
);

# Check them in with noop and "amnesty mode."
$checkin_opts = {
    override_args => {all => 1},
    noop => 1,
    void_overdues => 1
};
for my $circ (@{$circs}) {
    $checkin_opts->{copy_id} = $circ->target_copy;
    my $r = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.checkin.override',
        $authtoken,
        $checkin_opts
    );
}

# Find the patron's holds
$holds = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.hold_request.search.atomic',
    {usr => $patron->id}
);
ok(
    ref $holds && @{$holds},
    'Got holds for BR1 patron'
);

# Delete the patron to instantly archive the circs and holds
$rv = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.delete',
    $authtoken,
    $patron->id,
    undef
);
is(
    $rv,
    1,
    'Patron is deleted'
);

# Check aged circs and aged holds:
@circ_ids = map {$_->id} @{$circs};
@hold_ids = map {$_->id} @{$holds};
$aged_circs = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.aged_circulation.search.atomic',
    {id => [@circ_ids], usr_post_code => {'<>' => undef}, usr_birth_year => {'<>' => undef}}
);
is(
    scalar(@{$aged_circs}),
    scalar(@{$circs}),
    'Got correct number of aged circs'
);
$aged_holds = $U->simplereq(
    'open-ils.cstore',
    'open-ils.cstore.direct.action.aged_hold_request.search.atomic',
    {id => [@hold_ids], usr_post_code => {'<>' => undef}, usr_birth_year => {'<>' => undef}}
);
is(
    scalar(@{$aged_holds}),
    scalar(@{$holds}),
    'Got correct number of aged holds'
);

# Logout just to be pedantic
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

done_testing();
