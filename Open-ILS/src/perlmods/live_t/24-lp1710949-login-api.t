#!perl

use Test::More tests => 22;

diag("Tests open-ils.auth.login");

use strict; use warnings;
use OpenILS::Utils::TestUtils;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Cache;
our $U = "OpenILS::Application::AppUtils";

OpenILS::Utils::TestUtils->new->bootstrap;

my $resp = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.login', {
        username => 'admin',
        password => 'demo123',
        type => 'staff'
    }
);

is($resp->{textcode}, 'SUCCESS', 'Admin username login OK');

my $authtoken = $resp->{payload}->{authtoken};
ok($authtoken, 'Have an authtoken');

$resp = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.session.retrieve', $authtoken);

ok( 
    (ref($resp) && !$U->event_code($resp) && $resp->usrname eq 'admin'), 
    'Able to retrieve session'
);

$resp = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.login', {
        username => 'admin',
        password => 'demo123x', # bad password
        type => 'staff'
    }
);

isnt($resp->{textcode}, 'SUCCESS', 'Admin bad password rejected');

$resp = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.login', {
        barcode => '99999381970',
        password => 'montyc1234',
        type => 'staff'
    }
);

is($resp->{textcode}, 'SUCCESS', '99999381970 login OK');

$resp = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.login', {
        identifier => 'br1mclark',
        password => 'montyc1234',
        type => 'staff'
    }
);

is($resp->{textcode}, 'SUCCESS', 'Identifier check for br1mclark OK');

foreach my $i (1..15) {
    $resp = $U->simplereq(
        'open-ils.auth',
        'open-ils.auth.login', {
            identifier => 'br1mclark',
            password => 'justplainwrong',
            type => 'staff'
        }
    );
    isnt($resp->{textcode}, 'SUCCESS', "Attempt $i: wrong password br1mclark does not work");
}

$resp = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.login', {
        identifier => 'br1mclark',
        password => 'montyc1234',
        type => 'staff'
    }
);
isnt($resp->{textcode}, 'SUCCESS', '... and consequently multiple failed attempts block');

# and clean up
my $cache = OpenSRF::Utils::Cache->new("global", 0);
$cache->delete_cache('oils_auth_br1mclark_count');
