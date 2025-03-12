#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use Digest::MD5 qw(md5_hex);
use Time::HiRes qw(time);
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
#           ('vendor.quipu.ecard.patron_profile', 4, 1),
#           ('vendor.quipu.ecard.account_id', 4, 1234),
#           ('opac.ecard_registration_enabled', 1, true);
my $VENDOR_PASSWORD = 'ecard_password';
my $ECARD_SUBMIT_URL = "https://$host/eg/opac/ecard/submit";

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

sub make_request {
    my ($ua, $params) = @_;
    my $request = POST $ECARD_SUBMIT_URL, $params;
    return $ua->request($request);
}

# Begin Tests

subtest 'API Tests' => sub {
    my $ua = create_ua();

    # Test 1: Valid submission
    {
        my $response = make_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        #print('Test 1: response' . Dumper($response) . "\n");
        ok($response->is_success, 'Valid submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Response is valid JSON');
    }

    # Test 2: Expired token
    {
        my $old_timestamp = (int(time()) - 3600*1000);  # 1 hour ago
        my $response = make_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET, $old_timestamp),
        });
        ok(!$response->is_success, 'Expired token submission fails');
    }

    # Test 3: Future token
    {
        my $future_timestamp = (int(time()) + 3600*1000);  # 1 hour ahead
        my $response = make_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET, $future_timestamp),
        });
        ok(!$response->is_success, 'Future token submission fails');
    }

    # Test 4: Very old token
    {
        my $very_old_timestamp = (int(time()) - 365 * 24 * 3600*1000);  # 1 year ago
        my $response = make_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET, $very_old_timestamp),
        });
        ok(!$response->is_success, 'Very old token submission fails');
    }

    # Test 5: Very future token
    {
        my $very_future_timestamp = (int(time()) + 365 * 24 * 3600*1000);  # 1 year ahead
        my $response = make_request($ua, {
            %ecard_data,
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET, $very_future_timestamp),
        });
        ok(!$response->is_success, 'Very future token submission fails');
    }

    # Test 6: API test mode
    {
        my $response = make_request($ua, {
            testmode => "API",
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        ok($response->is_success, 'API test mode succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'API test mode response is valid JSON');
    }

    # Test 7: Data mode test
    {
        my $response = make_request($ua, {
            datamode => "all",
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        ok($response->is_success, 'Data mode test succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Data mode response is valid JSON');
    }

    # Test 8: Username taken
    {
        my $response = make_request($ua, {
            %ecard_data,
            usrname => "99999360638",
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        #print('Test 8: response' . Dumper($response) . "\n");
        ok($response->is_success, 'Valid submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Response is valid JSON');
        is($content->{status}, 'USERNAME_TAKEN', 'Username is already taken');
    }

    # Test 9: Username available
    {
        my $response = make_request($ua, {
            %ecard_data,
            usrname => 'purple_pineapple',
            vendor_username => $VENDOR_USERNAME,
            vendor_password => $VENDOR_PASSWORD,
            security_token => generate_ecard_token($SHARED_SECRET),
        });
        #print('Test 9: response' . Dumper($response) . "\n");
        ok($response->is_success, 'Valid submission succeeds');
        my $content = eval { decode_json($response->decoded_content) };
        ok(!$@, 'Response is valid JSON');
        isnt($content->{status}, 'USERNAME_TAKEN', 'Username is available');
    }
};

done_testing();
