#!perl
use strict; use warnings;
use Test::More;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);
use B qw(svref_2object SVf_IOK);

my $script = OpenILS::Utils::TestUtils->new();
my $U = 'OpenILS::Application::AppUtils';

# Setup some useful values for later:
use constant {
    WORKSTATION => 'LP1923076-Test-Scalar-Return-Type',
    USERNAME => 'br1mtownsend',
    PASSWORD => 'demo123',
    BR1_ID => 4
};

my $credentials = {
    username => USERNAME,
    password => PASSWORD,
    type => 'staff'
};

diag('LP1923076 Test Scalar Return Type');

# Skip tests if Perl version older than 5.28.0
if ($] lt '5.028000') {
    plan skip_all => "Tests irrelevant on Perl version $]";
} else {
    plan tests => 6;
}

# Login and register workstation
my $authtoken = $script->authenticate($credentials);
BAIL_OUT('Must log in') unless ($authtoken);
my $ws = $script->find_or_register_workstation(WORKSTATION, BR1_ID);
BAIL_OUT('Need workstation') if (ref $ws);
$script->logout();
undef($authtoken);

# Login again for remaining tests.
$credentials->{password} = PASSWORD;
$credentials->{workstation} = WORKSTATION;
$authtoken = $script->authenticate($credentials);
BAIL_OUT('Need to log in') unless ($authtoken);
END {
    $script->logout() if $authtoken;
}

# Initial smoke tests.
ok(
    is_integer(0),
    '0 is integer'
);

ok(
    !is_integer("0"),
    '"0" is not a integer'
);

# Check open-ils.actor.user.hold_requests.count.
my $result = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.hold_requests.count',
    $authtoken,
    1,
    BR1_ID
);

ok(
    is_integer($result->{total}),
    $result->{total} . ' is integer'
);

ok(
    is_integer($result->{ready}),
    $result->{ready} . ' is integer'
);

ok(
    is_integer($result->{behind_desk}),
    $result->{behind_desk} . ' is integer'
);

# Check open-ils.storage.action.live_holds.wide_hash
$result = $U->simplereq(
    'open-ils.storage',
    'open-ils.storage.action.live_holds.wide_hash',
    {pickup_lib=>0}
);

ok(
    is_integer($result),
    $result . ' is integer'
);

# Check if argument is integer.
sub is_integer {
    my $x = shift;
    my $sv = svref_2object(\$x);
    return $sv->FLAGS & SVf_IOK;
}
