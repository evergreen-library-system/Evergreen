#!perl

use Test::More tests => 4;

diag("Simple tests against the open-ils.auth service, memcached, and the stock test data.");

use strict; use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();

#----------------------------------------------------------------
# The tests...  assumes stock sample data
#----------------------------------------------------------------

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});

my $authtoken = $script->authtoken;

ok(
    $authtoken,
    'Have an authtoken'
);
is(
    $script->authtime,
    7200,
    'Default authtime for staff login is 7200 seconds'
);

my $cached_obj = $script->cache()->get_cache("oils_auth_$authtoken");

ok(
    ref $cached_obj,
    'Can retrieve authtoken from memcached'
);

$script->logout();

$cached_obj = $script->cache()->get_cache("oils_auth_$authtoken");
ok(
    ! $cached_obj,
    'Authtoken is removed from memcached after logout'
);

