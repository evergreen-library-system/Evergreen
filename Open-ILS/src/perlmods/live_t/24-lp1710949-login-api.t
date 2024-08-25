#!perl

use Test::More tests => 27;

diag("Tests open-ils.auth.login");

use strict; use warnings;
use OpenILS::Utils::TestUtils;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw/md5_hex/;
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
        password => 'demo123',
        type => 'staff'
    }
);

is($resp->{textcode}, 'SUCCESS', '99999381970 login OK');

$resp = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.login', {
        identifier => 'br1mclark',
        password => 'demo123',
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
        password => 'demo123',
        type => 'staff'
    }
);
isnt($resp->{textcode}, 'SUCCESS', '... and consequently multiple failed attempts block');

# and clean up
my $cache = OpenSRF::Utils::Cache->new("global", 0);
$cache->delete_cache('oils_auth_br1mclark_count');

# test for LP#1830642
my $new_pwd = 'password%';

my $user = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.fleshed.retrieve_by_barcode',
    $authtoken,
    '99999381970'
);
$user->passwd($new_pwd);
$resp = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.patron.update',
    $authtoken,
    $user
);
isa_ok($resp, 'Fieldmapper::actor::user', 'test password updated');

my $seed = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.authenticate.init',
    'br1mclark'
);
ok(defined $seed, 'Got an auth seed');

my $hashed_pwd = md5_hex($seed . md5_hex($new_pwd));
$resp = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.authenticate.complete',
    {
        username => 'br1mclark',
        password => $hashed_pwd,
        type => 'staff'
    }
);
is($resp->{textcode}, 'SUCCESS', '.complete succeeds when password contains %');

$resp = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.login', {
        identifier => 'br1mclark',
        password => $new_pwd,
        type => 'staff'
    }
);
is($resp->{textcode}, 'SUCCESS', '.login succeeds when password contains %');

# cleanup
my $restored_user = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.fleshed.retrieve_by_barcode',
    $authtoken,
    '99999381970'
);
$restored_user->passwd('demo123');
$resp = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.patron.update',
    $authtoken,
    $restored_user
);
isa_ok($resp, 'Fieldmapper::actor::user', 'test password reverted');

