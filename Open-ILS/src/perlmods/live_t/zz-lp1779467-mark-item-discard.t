#!perl
use strict; use warnings;
use Test::More tests => 17;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);

my $script = OpenILS::Utils::TestUtils->new();
my $U = 'OpenILS::Application::AppUtils';

diag("Test LP 1779467 Enhance Mark Item Discard/Weed.");

use constant {
    BR1_ID => 4,
    BR3_ID => 6,
    WORKSTATION => 'BR1-lp1779467-test-mark-item-discard'
};

# We are deliberately NOT using the admin user to check for a perm failure.
my $credentials = {
    username => 'br1mtownsend',
    password => 'demo123',
    type => 'staff'
};

# Log in as staff.
my $authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    'Logged in'
) or BAIL_OUT('Must log in');

# Find or register workstation.
my $ws = $script->find_or_register_workstation(WORKSTATION, BR1_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
) or BAIL_OUT('Need Workstation');

# Logout.
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# Login with workstation.
$credentials->{workstation} = WORKSTATION;
$credentials->{password} = 'demo123';
$authtoken = $script->authenticate($credentials);
ok(
    $script->authtoken,
    'Logged in with workstation'
) or BAIL_OUT('Must log in');

# Find available copy at BR1
my $acps = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.acp.atomic',
    $authtoken,
    {circ_lib => BR1_ID, status => OILS_COPY_STATUS_AVAILABLE},
    {limit => 1}
);
my $copy = $acps->[0];
isa_ok(
    ref $copy,
    'Fieldmapper::asset::copy',
    'Got available copy from BR1'
);

# Mark it discard/weed.
my $result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.mark_item_discard',
    $authtoken,
    $copy->id()
);
is(
    $result,
    1,
    'Mark available copy Discard/Weed'
);

# Check its status.
$copy = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken,
    $copy->id()
);
is(
    $copy->status(),
    OILS_COPY_STATUS_DISCARD,
    'Copy has Discard/Weed status'
);

# Find available copy at BR3.
$acps = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.acp.atomic',
    $authtoken,
    {circ_lib => BR3_ID, status => OILS_COPY_STATUS_AVAILABLE},
    {limit => 1}
);
$copy = $acps->[0];
isa_ok(
    ref $copy,
    'Fieldmapper::asset::copy',
    'Got available copy from BR3'
);

# Attempt to mark it discard/weed.
# Should fail with a perm error.
$result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.mark_item_discard',
    $authtoken,
    $copy->id()
);
is(
    $result->{textcode},
    'PERM_FAILURE',
    'Mark BR3 copy Discard/Weed'
);

# Find checked out copy at BR1.
$acps = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.acp.atomic',
    $authtoken,
    {circ_lib => BR1_ID, status => OILS_COPY_STATUS_CHECKED_OUT},
    {limit => 1}
);
$copy = $acps->[0];
isa_ok(
    ref $copy,
    'Fieldmapper::asset::copy',
    'Got checked out copy from BR1'
);

# Mark it discard/weed with handle_checkin: 1.
$result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.mark_item_discard',
    $authtoken,
    $copy->id(),
    {handle_checkin => 1}
);
ok(
    $result == 1,
    'Mark checked out item discard'
);

# Check its status.
$copy = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken,
    $copy->id()
);
is(
    $copy->status(),
    OILS_COPY_STATUS_DISCARD,
    'Checked out copy has Discard/Weed status'
);

# Check that it is no longer checked out.
my $circ = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.circ',
    $authtoken,
    {target_copy => $copy->id(), checkin_time => undef}
);
ok(
    ! defined $circ,
    'No circulation for marked copy'
);

# Find another checked out copy at BR1.
$acps = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.acp.atomic',
    $authtoken,
    {circ_lib => BR1_ID, status => OILS_COPY_STATUS_CHECKED_OUT},
    {limit => 1}
);
$copy = $acps->[0];
isa_ok(
    ref $copy,
    'Fieldmapper::asset::copy',
    'Got another checked out copy from BR1'
);

# Mark it discard/weed with handle_checkin: 0.
$result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.mark_item_discard',
    $authtoken,
    $copy->id(),
    {handle_checkin => 0}
);
# Check that we got the appropriate event: ITEM_TO_MARK_CHECKED_OUT
is(
    $result->{textcode},
    'ITEM_TO_MARK_CHECKED_OUT',
    'Mark second checked out item discard'
);

# Check its status.
$copy = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken,
    $copy->id()
);
is(
    $copy->status(),
    OILS_COPY_STATUS_CHECKED_OUT,
    'Second checked out copy has Checked Out status'
);

# Check that it is still checked out.
$circ = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.circ',
    $authtoken,
    {target_copy => $copy->id(), checkin_time => undef}
);
isa_ok(
    $circ,
    'Fieldmapper::action::circulation',
    'Second copy still has a circulation'
);

# We could add more tests for other conditions, i.e. a copy in transit
# and for marking other statuses.

# Logout
$script->logout(); # Not a test, just to be pedantic.
