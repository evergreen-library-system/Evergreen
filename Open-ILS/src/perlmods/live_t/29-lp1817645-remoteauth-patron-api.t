#!perl

use Test::More;

# need at least 6.07 of LWP::Protocol::https to avoid
# an issue where it cannot successfully bypass a
# certificate check of localhost
eval 'use LWP::Protocol::https 6.07';
if ($@) {
    plan skip_all => 'LWP::Protocol::https 6.0.7 or later required for live tests of remoteauth' if $@;
} else {
    plan tests => 10;
}

diag("Tests RemoteAuth patron auth/retrieval");

use strict; use warnings;
use OpenILS::Utils::TestUtils;
use MIME::Base64;
use HTTP::Request;
use LWP::UserAgent;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
our $U = "OpenILS::Application::AppUtils";

OpenILS::Utils::TestUtils->new->bootstrap;

my $not_found = { barcode => '99999393000', password => 'nonexistentbarcode' };
my $expired = { barcode => '99999393001', password => 'demo123' };
my $deleted = { barcode => '99999393002', password => 'demo123' };
my $barred = { barcode => '99999393003', password => 'demo123' };
my $valid = { barcode => '99999393004', password => 'demo123' };
my $inactive = { barcode => '99999393005', password => 'demo123' };
my $external = { barcode => '99999393100', password => 'demo123' };

# context org is SYS1, test user's home OU is BR1;
# use BR3 (under SYS2) to test external users
my $external_org = 6; # BR3

my $staff_login = $U->simplereq(
    'open-ils.auth',
    'open-ils.auth.login', {
        username => 'admin',
        password => 'demo123',
        type => 'staff'
    }
);
is($staff_login->{textcode}, 'SUCCESS', 'Staff login OK');
my $e = new_editor( authtoken => $staff_login->{payload}->{authtoken} );
$e->init;

my $client = LWP::UserAgent->new;
$client->ssl_opts(
    SSL_verify_mode => 0,
    verify_hostname => 0
);

# my $res = $client->request( $method, $uri, $headers, $content, $request_timeout );


######################################################################

# requests:
# - validate barcode only?
# - validate barcode + PIN
# - retrieve user and check for required fields in response

# test cases:
# - valid user with username or barcode (opac.barcode_regex)
# - valid user with barcode prefix
# - valid user with barcode
# - invalid password
# - barcode not found
# - user is deleted
# - user is expired
# - user is barred
# - user has non-blocking penalties, auth/retrieval succeeds
# - user has blocking penalties
# - user exists, but home OU is not in scope

# not currently supported:
# - AuthProxy: services should use the remote auth server directly
# - opted-in patrons: these are external patrons and thus not auth'd

######################################################################

#---------------------------------------------------------------------
# Basic access authentication (RFC 7617)
#---------------------------------------------------------------------
# - endpoint: /api/basicauth
# - client auth: none
# - request: includes "Authorization: Basic <credentials>" header,
#   credentials = Base64-encoded "id:password" string
# - response: HTTP 200 on success, 401 with WWW-Authenticate header 
#   field on failure
# - does not return patron info
#---------------------------------------------------------------------
sub basic_request {
    my ($u, $password) = @_;
    my $barcode = $u->{barcode};
    $password ||= $u->{password};
    my $resp = $client->get(
        "https://localhost/api/basicauth",
        'Authorization' => 'Basic ' . encode_base64("$barcode:$password")
    );
    return $resp->code;
}

my $basic_not_found = basic_request($not_found);
is ( $basic_not_found, '403', 'Basic request for nonexistent barcode correctly returned 403' );

my $basic_success = basic_request($valid);
is( $basic_success, '200', 'Basic request for valid patron OK' );

# invalid password
my $basic_invalid_pw = basic_request($valid, 'badpassword');
is( $basic_invalid_pw, '403', 'Basic request with invalid password correctly returned 403' );

# user is deleted
my $basic_deleted = basic_request($deleted);
is( $basic_deleted, '403', 'Basic request for deleted user correctly returned 403' );

# user is expired
my $basic_expired = basic_request($expired);
is( $basic_expired, '403', 'Basic request for expired user correctly returned 403' );

# user is inactive
my $basic_inactive = basic_request($inactive);
is( $basic_inactive, '403', 'Basic request for inactive user correctly returned 403' );

# user is barred
my $basic_barred = basic_request($barred);
is( $basic_barred, '403', 'Basic request for barred user correctly returned 403' );

# home OU is not in scope
my $basic_external = basic_request($external);
is( $basic_external, '403', 'Basic request for external user correctly returned 403' );

# TODO: user has blocking penalties

# TODO: user has non-blocking penalties, auth/retrieval succeeds



# TODO: EZProxy external script authentication:
# - endpoint: /remoteauth/ezproxy/<shortname>/<id>/<password>
# - client auth: none
# - request: GET with user and pass params, as above
# - response: "+VALID" if auth succeeds


# verify user activity based on the above tests
my $user = $U->fetch_user_by_barcode( $valid->{barcode} );
my $basic_activity = $e->search_actor_usr_activity([{usr => $user->id, etype => 1001}]);
ok(scalar(@$basic_activity) > 0, 'Basic request for valid patron is recorded in user activity');

