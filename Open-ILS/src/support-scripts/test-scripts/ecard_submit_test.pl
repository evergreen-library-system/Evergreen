#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Request::Common;
use JSON;
use Digest::MD5 qw(md5_hex);
use Time::HiRes qw(time);
use DateTime;
use DateTime::Format::ISO8601;
use Data::Dumper;

# Configuration
my $host = $ENV{TEST_HOST} || 'localhost';
my $SHARED_SECRET = 'your_shared_secret_here';
my $VENDOR_USERNAME = 'admin';
#  TODO: add this to concerto: SELECT actor.set_passwd(1, 'ecard_vendor', 'ecard_password');
#  TODO: insert into actor.org_unit_setting (name, org_unit, value) values
#           ('vendor.quipu.ecard.shared_secret', 1, '"your_shared_secret_here"'),
#           ('vendor.quipu.ecard.admin_org_unit', 1, 4),
#           ('vendor.quipu.ecard.barcode_length', 4, 11),
#           ('vendor.quipu.ecard.barcode_prefix', 4, '"321"'),
#           ('vendor.quipu.ecard.calculate_checkdigit', 4, 'true'),
#           ('vendor.quipu.ecard.admin_usrname', 4, '"admin"'),
#           ('vendor.quipu.ecard.patron_profile', 4, 2),
#           ('vendor.quipu.ecard.account_id', 4, 1234),
#           ('opac.ecard_registration_enabled', 1, true),
#           ('opac.ecard_renewal_enabled', 1, true);
my $VENDOR_PASSWORD = 'ecard_password';
my $ECARD_SUBMIT_URL = "https://$host/eg/opac/ecard/submit";
my $OSRF_GATEWAY_URL = "https://$host/osrf-gateway-v1";

# Test data
my %ecard_data = (
    first_given_name => 'John',
    second_given_name => 'Michael',
    family_name => 'Doe',
    email => 'johndoe@example.com',
    dob => '1990-01-15',
    day_phone => '555-123-4567',
    home_ou => '4',
    passwd => 'demo123',
    ident_type => '1',
    ident_value => 'DL12345678',
    physical_street1 => '123 Main St',
    physical_city => 'Anytown',
    physical_state => 'Anystate',
    physical_country => 'USA',
    physical_county => 'Anycounty',
    physical_post_code => '12345',
    mailing_street1 => '123 Main St',
    mailing_city => 'Anytown',
    mailing_state => 'Anystate',
    mailing_country => 'USA',
    mailing_county => 'Anycounty',
    mailing_post_code => '12345',
);

# Helper Functions
sub generate_ecard_token {
    my ($shared_secret, $custom_timestamp) = @_;
    my $timestamp = defined($custom_timestamp) ? $custom_timestamp : int(time());
    my $signature = md5_hex($timestamp . $shared_secret);
    return "$timestamp:$signature";
}

sub create_ua {
    return LWP::UserAgent->new(
        ssl_opts => {
            verify_hostname => 0,
            SSL_verify_mode => 0x00
        }
    );
}

sub ecard_submit_request {
    my ($ua, $params) = @_;
    my $request = POST $ECARD_SUBMIT_URL, $params;
    return $ua->request($request);
}

sub osrf_gateway_request {
    my ($ua, $params) = @_;
    my $request = POST $OSRF_GATEWAY_URL, $params;
    return $ua->request($request);
}

# Begin Tests

subtest 'API Tests' => sub {
    my $ua = create_ua();

    # Test: Valid submission
    {
        my $response = ecard_submit_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        ok($response->is_success, 'Registration submission succeeds (but not necessarily the Registration itself)');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Response is valid JSON');
        diag(Dumper($content || (defined $response->title ? $response->title : $response)));
    }

    # Test: Expired token
    {
        my $old_timestamp = (int(time()) - 3600*1000);  # 1 hour ago
        my $response = ecard_submit_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET, $old_timestamp),
        });
        ok(!$response->is_success, 'Registration submission with Expired token fails');
        diag(Dumper(defined $response->title ? $response->title : $response));
    }

    # Test: Future token
    {
        my $future_timestamp = (int(time()) + 3600*1000);  # 1 hour ahead
        my $response = ecard_submit_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET, $future_timestamp),
        });
        ok(!$response->is_success, 'Registration submission with Future token fails');
        diag(Dumper(defined $response->title ? $response->title : $response));
    }

    # Test: Very old token
    {
        my $very_old_timestamp = (int(time()) - 365 * 24 * 3600*1000);  # 1 year ago
        my $response = ecard_submit_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET, $very_old_timestamp),
        });
        ok(!$response->is_success, 'Registration submission with Very old token fails');
        diag(Dumper(defined $response->title ? $response->title : $response));
    }

    # Test: Very future token
    {
        my $very_future_timestamp = (int(time()) + 365 * 24 * 3600*1000);  # 1 year ahead
        my $response = ecard_submit_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET, $very_future_timestamp),
        });
        ok(!$response->is_success, 'Registration submission with Very future token fails');
        diag(Dumper(defined $response->title ? $response->title : $response));
    }

    # Test: API test mode
    {
        my $response = ecard_submit_request($ua, {
            testmode => "API",
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        ok($response->is_success, 'API test mode submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'API test mode response is valid JSON');
        diag(Dumper($content || (defined $response->title ? $response->title : $response)));
    }

    # Test: Data mode test
    {
        my $response = ecard_submit_request($ua, {
            datamode => "all",
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        ok($response->is_success, 'Data mode test submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Data mode response is valid JSON');
        diag(Dumper($content || (defined $response->title ? $response->title : $response)));
    }

    # Test: Username taken
    {
        my $response = ecard_submit_request($ua, {
            %ecard_data,
            usrname => "99999360638",
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        ok($response->is_success, 'Registration submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Response is valid JSON');
        is($content->{status}, 'USERNAME_TAKEN', 'Username is already taken');
        diag(Dumper($content || (defined $response->title ? $response->title : $response)));
    }

    my $patron_id;

    my $usrname = 'purple_pineapple_' . time();

    my $today_dt = DateTime->now(time_zone => 'local');
    my $today_iso = $today_dt->iso8601();
    my $today_plus_15_dt = DateTime->now(time_zone => 'local')->add(days => 15);
    my $today_plus_15_iso = $today_plus_15_dt->iso8601();
    my $today_plus_60_dt = DateTime->now(time_zone => 'local')->add(days => 60);
    my $today_plus_60_iso = $today_plus_60_dt->iso8601();
    my $today_minus_60_dt = DateTime->now(time_zone => 'local')->subtract(days => 60);
    my $today_minus_60_iso = $today_minus_60_dt->iso8601();

    # Test: User registered (already expired for subsequent renewal testing)
    {
        my $response = ecard_submit_request($ua, {
            %ecard_data,
            expire_date => $today_minus_60_iso, # This will override the default provided by the permission group
            usrname => $usrname,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        ok($response->is_success, 'Registration submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Response is valid JSON');
        is($content->{status}, 'OK', 'User registered');
        diag(Dumper($content || (defined $response->title ? $response->title : $response)));
        $patron_id = $content->{patron_id};
        diag("patron_id = $patron_id");
    }

    # https://host/osrf-gateway-v1?service=open-ils.auth&method=open-ils.auth.login&param=

    my $auth_token;

    # Test: auth token
    {
        my $response = osrf_gateway_request($ua, [
            service => 'open-ils.auth',
            method => 'open-ils.auth.login',
            param => encode_json({ username => "admin", password => "demo123" }) # for expediency; the vendor credentials we added earlier will not suffice here currently
        ]);
        ok($response->is_success, 'Login submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        if (defined $content->{payload} && defined $content->{payload}->[0] && defined $content->{payload}->[0]->{payload} && defined $content->{payload}->[0]->{payload}->{authtoken}) {
            $auth_token = $content->{payload}->[0]->{payload}->{authtoken};
        }
        ok($auth_token, 'Received authtoken');
        diag(Dumper($auth_token || $content));
    }

    my $expire_date;

    # open-ils.actor.user.opac.renewal
    {
        my $response = osrf_gateway_request($ua, [
            service => 'open-ils.actor',
            method => 'open-ils.actor.user.opac.renewal',
            param => encode_json($auth_token),
            param => encode_json($patron_id)
        ]);
        ok($response->is_success, 'Patron retrieval submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Response is valid JSON');
        is($content->{status}, '200', 'Retrieval succeeded');
        my $user = $content->{payload}[0]->{user};
        is($user->{email}, $ecard_data{'email'}, 'Email matches');
        $expire_date = $user->{expire_date};
        diag("expire_date = $expire_date");
        #diag(Dumper($content || (defined $response->title ? $response->title : $response)));
    }

    my $formatter = DateTime::Format::ISO8601->new();
    my $dt_date = $formatter->parse_datetime($expire_date);
    $dt_date->add( years => 1 );
    my $new_expire_date = $dt_date->strftime('%Y-%m-%dT%H:%M:%S%z');

    # Test: User editing (for renewal)
    {
        my $response = ecard_submit_request($ua, {
            patron_id => $patron_id,
            %ecard_data,
            expire_date => $new_expire_date, # this will supplant the one coming from %ecard_data
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        ok($response->is_success, 'Renewal submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        #diag(Dumper($content || (defined $response->title ? $response->title : $response)));
        ok(!$@, 'Response is valid JSON');
        is($content->{status}, undef, 'User not eligible for renewal'); # This is only true in this case because the user has not logged in immediately prior to the check
    }

    # open-ils.actor.user.opac.renewal
    {
        my $response = osrf_gateway_request($ua, [
            service => 'open-ils.actor',
            method => 'open-ils.actor.user.opac.renewal',
            param => encode_json($auth_token),
            param => encode_json($patron_id)
        ]);
        ok($response->is_success, 'Patron retrieval submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Response is valid JSON');
        is($content->{status}, '200', 'Retrieval succeeded');
        my $user = $content->{payload}[0]->{user};
        is($user->{email}, $ecard_data{'email'}, 'Email matches');
        my $testing_expire_date = $user->{expire_date};
        isnt($testing_expire_date, $new_expire_date, 'Expire date did not change');
        diag("expire_date = $expire_date");
        #diag(Dumper($content || (defined $response->title ? $response->title : $response)));
    }

    my $patron_ua = LWP::UserAgent->new(
        cookie_jar => HTTP::Cookies->new,
        ssl_opts => {
            verify_hostname => 0,
            SSL_verify_mode => 0x00
        }
    );

    my $login_resp = $patron_ua->post(
        "https://$host/eg/opac/login", {
          username => $usrname,
          password => $ecard_data{'passwd'},
        }
    );

    # diag(Dumper($login_resp));

    ok($login_resp->is_redirect, 'Patron login is successful (redirects)');

    # This sets an eligibility key in a cache that gets checked

    # Test: User editing (for renewal)
    {
        my $response = ecard_submit_request($ua, {
            patron_id => $patron_id,
            %ecard_data,
            expire_date => $new_expire_date, # this will supplant the one coming from %ecard_data
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        ok($response->is_success, 'Renewal submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        diag(Dumper($content || (defined $response->title ? $response->title : $response)));
        ok(!$@, 'Response is valid JSON');
        isnt($content->{status}, undef, 'User should be eligible');
    }

    # open-ils.actor.user.opac.renewal
    {
        my $response = osrf_gateway_request($ua, [
            service => 'open-ils.actor',
            method => 'open-ils.actor.user.opac.renewal',
            param => encode_json($auth_token),
            param => encode_json($patron_id)
        ]);
        ok($response->is_success, 'Patron retrieval submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Response is valid JSON');
        is($content->{status}, '200', 'Retrieval succeeded');
        my $user = $content->{payload}[0]->{user};
        is($user->{email}, $ecard_data{'email'}, 'Email matches');
        my $testing_expire_date = $user->{expire_date};
        is($testing_expire_date, $new_expire_date, 'Expire date did change');
        diag("expire_date = $expire_date");
        #diag(Dumper($content || (defined $response->title ? $response->title : $response)));
    }

};

done_testing();
