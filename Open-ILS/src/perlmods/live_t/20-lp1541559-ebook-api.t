#!perl
use strict; use warnings;
use Test::More tests => 24; # XXX
use OpenILS::Utils::TestUtils;

diag("Tests Ebook API");

# ------------------------------------------------------------ 
# 1. Set up test environment.
# ------------------------------------------------------------ 

use constant EBOOK_API_VENDOR => 'ebook_test';
use constant EBOOK_API_OU => 1;

# Title IDs:
# 001 - checked out to test user
# 002 - not available (checked out to another user)
# 003 - available
# 004 - not found (invalid/does not exist in external system)

# Patrons.
use constant EBOOK_API_PATRON_USERNAME  => '99999359616';
use constant EBOOK_API_PATRON_PASSWORD  => 'demo123';
use constant EBOOK_API_PATRON_NOT_FOUND => 'patron-not-found';

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $ebook_api = $script->session('open-ils.ebook_api');

# ------------------------------------------------------------ 
# 2. Sessions.
# ------------------------------------------------------------ 

# Initiate a new EbookAPI session and get a session ID.
# Returns undef unless a new session was created.
my $session_id_req = $ebook_api->request(
    'open-ils.ebook_api.start_session', EBOOK_API_VENDOR, EBOOK_API_OU);
my $session_id = $session_id_req->recv->content;
ok($session_id, 'Initiated an EbookAPI session');

# Check that an EbookAPI session exists matching our session ID.
my $ck_session_id_req = $ebook_api->request(
	'open-ils.ebook_api.check_session', $session_id, EBOOK_API_VENDOR, EBOOK_API_OU);
my $ck_session_id = $ck_session_id_req->recv->content;
ok($ck_session_id eq $session_id, 'Validated existing EbookAPI session');

# Given an invalid or expired session ID, fallback to initiating 
# a new EbookAPI session, which gives us a new session ID.
# Returns undef unless a new session was created.
my $new_session_id_req = $ebook_api->request(
    'open-ils.ebook_api.check_session', '', EBOOK_API_VENDOR, EBOOK_API_OU);
my $new_session_id = $new_session_id_req->recv->content;
ok($new_session_id, 'Initiated new EbookAPI session when valid session ID not provided');

# ------------------------------------------------------------ 
# 3. Title availability and holdings.
# ------------------------------------------------------------ 

# Title details for valid title ID.
my $title_001_details_req = $ebook_api->request(
    'open-ils.ebook_api.title.details', $session_id, '001');
my $title_001_details = $title_001_details_req->recv->content;
ok(ref($title_001_details) && $title_001_details->{title}, 'Title details check 1/2 (valid title)');

# Title details for invalid title ID.
my $title_004_details_req = $ebook_api->request(
    'open-ils.ebook_api.title.details', $session_id, '004');
my $title_004_details = $title_004_details_req->recv->content;
ok(ref($title_004_details) && $title_004_details->{error}, 'Title details check 1/2 (invalid title returns error message)');

# Title is not available.
my $title_001_avail_req = $ebook_api->request(
    'open-ils.ebook_api.title.availability', $session_id, '001');
my $title_001_avail = $title_001_avail_req->recv->content;
is($title_001_avail, 0, 'Availability check 1/3 (not available)');

# Title is available.
my $title_003_avail_req = $ebook_api->request(
    'open-ils.ebook_api.title.availability', $session_id, '003');
my $title_003_avail = $title_003_avail_req->recv->content;
is($title_003_avail, 1, 'Availability check 2/3 (available)');

# Title is not found (availability lookup returns undef).
my $title_004_avail_req = $ebook_api->request(
    'open-ils.ebook_api.title.availability', $session_id, '004');
my $title_004_avail = (defined $title_004_avail_req && defined $title_004_avail_req->recv) ? $title_004_avail_req->recv->content : undef;
is($title_004_avail, undef, 'Availability check 3/3 (not found)');

# Title has holdings, none available.
my $title_001_holdings_req = $ebook_api->request(
    'open-ils.ebook_api.title.holdings', $session_id, '001');
my $title_001_holdings = $title_001_holdings_req->recv->content;
ok(ref($title_001_holdings) && $title_001_holdings->{copies_owned} == 1 && $title_001_holdings->{copies_available} == 0 && $title_001_holdings->{formats}->[0]->{name} eq 'ebook', 'Holdings check 1/3 (1 owned, 0 available)');

# Title has holdings, one copy available.
my $title_003_holdings_req = $ebook_api->request(
    'open-ils.ebook_api.title.holdings', $session_id, '003');
my $title_003_holdings = $title_003_holdings_req->recv->content;
ok(ref($title_003_holdings) && $title_003_holdings->{copies_owned} == 1 && $title_003_holdings->{copies_available} == 1 && $title_003_holdings->{formats}->[0]->{name} eq 'ebook', 'Holdings check 2/3 (1 owned, 1 available)');

# Title not found, no holdings.
my $title_004_holdings_req = $ebook_api->request(
    'open-ils.ebook_api.title.holdings', $session_id, '004');
my $title_004_holdings = $title_004_holdings_req->recv->content;
ok(ref($title_004_holdings) && $title_004_holdings->{copies_owned} == 0 && $title_004_holdings->{copies_available} == 0 && scalar(@{$title_004_holdings->{formats}}) == 0, 'Holdings check 3/3 (0 owned, 0 available)');

# ------------------------------------------------------------ 
# 4. Patron authentication and caching.
# ------------------------------------------------------------ 

# Authenticate our test patron.
$script->authenticate({
        username => EBOOK_API_PATRON_USERNAME,
        password => EBOOK_API_PATRON_PASSWORD,
        type => 'opac'
    });
ok($script->authtoken, 'Have an authtoken');
my $authtoken = $script->authtoken;

# open-ils.ebook_api.patron.cache_password
my $updated_cache_id_req = $ebook_api->request(
    'open-ils.ebook_api.patron.cache_password', $session_id, EBOOK_API_PATRON_PASSWORD);
my $updated_cache_id = $updated_cache_id_req->recv->content;
ok($updated_cache_id eq $session_id, 'Session cache was updated with patron password');

# ------------------------------------------------------------ 
# 5. Patron transactions.
# ------------------------------------------------------------ 

# open-ils.ebook_api.patron.get_checkouts
my $checkouts_req = $ebook_api->request(
    'open-ils.ebook_api.patron.get_checkouts', $authtoken, $session_id, EBOOK_API_PATRON_USERNAME);
my $checkouts = $checkouts_req->recv->content;
ok(ref($checkouts) && defined $checkouts->[0]->{title_id}, 'Retrieved ebook checkouts for patron');

# open-ils.ebook_api.patron.get_holds
my $holds_req = $ebook_api->request(
    'open-ils.ebook_api.patron.get_holds', $authtoken, $session_id, EBOOK_API_PATRON_USERNAME);
my $holds = $holds_req->recv->content;
ok(ref($holds) && defined $holds->[0]->{title_id}, 'Retrieved ebook holds for patron');

# open-ils.ebook_api.patron.get_transactions
my $xacts_req = $ebook_api->request(
    'open-ils.ebook_api.patron.get_transactions', $authtoken, $session_id, EBOOK_API_PATRON_USERNAME);
my $xacts = $xacts_req->recv->content;
ok(ref($xacts) && exists $xacts->{checkouts} && exists $xacts->{holds}, 'Retrieved transactions for patron');
ok(defined $xacts->{checkouts}->[0]->{title_id}, 'Retrieved transactions include checkouts');
ok(defined $xacts->{holds}->[0]->{title_id}, 'Retrieved transactions include holds');

# open-ils.ebook_api.checkout
my $checkout_req = $ebook_api->request(
    'open-ils.ebook_api.checkout', $authtoken, $session_id, '003', EBOOK_API_PATRON_USERNAME);
my $checkout = $checkout_req->recv->content;
ok(exists $checkout->{due_date}, 'Ebook checked out');

# open-ils.ebook_api.title.get_download_link
my $request_link = 'http://example.com/ebookapi/t/003';
my $download_link_req = $ebook_api->request(
    'open-ils.ebook_api.title.get_download_link', $authtoken, $session_id, $request_link);
my $download_link = $download_link_req->recv->content;
# Test module just returns the original request_link as the response.
ok($download_link eq $request_link, 'Received download link for ebook');

# open-ils.ebook_api.renew
my $renew_req = $ebook_api->request(
    'open-ils.ebook_api.renew', $authtoken, $session_id, '001', EBOOK_API_PATRON_USERNAME);
my $renew = $renew_req->recv->content;
ok(exists $renew->{due_date}, 'Ebook renewed');

# open-ils.ebook_api.checkin
my $checkin_req = $ebook_api->request(
    'open-ils.ebook_api.checkin', $authtoken, $session_id, '003', EBOOK_API_PATRON_USERNAME);
my $checkin = $checkin_req->recv->content;
ok(ref($checkin) && !exists $checkin->{error_msg}, 'Ebook checked in');

# open-ils.ebook_api.cancel_hold
my $cancel_hold_req = $ebook_api->request(
    'open-ils.ebook_api.cancel_hold', $authtoken, $session_id, '002', EBOOK_API_PATRON_USERNAME);
my $cancel_hold = $cancel_hold_req->recv->content;
ok(ref($cancel_hold) && !exists $checkin->{error_msg}, 'Ebook hold canceled');

# open-ils.ebook_api.place_hold
my $place_hold_req = $ebook_api->request(
    'open-ils.ebook_api.place_hold', $authtoken, $session_id, '002', EBOOK_API_PATRON_USERNAME);
my $place_hold = $place_hold_req->recv->content;
ok(exists $place_hold->{expire_date}, 'Ebook hold placed');

# TODO: suspend hold

