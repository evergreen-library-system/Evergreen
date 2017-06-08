#!/usr/bin/perl
use warnings;
use strict;

use LWP::UserAgent;
use HTTP::Request;
use JSON;
use Getopt::Long;
use MIME::Base64;
use Data::Dumper;

my $account_id;
my ($basic_token, $get_token, $client_key, $client_secret);
my ($api_endpoint, $content);
my $oauth_endpoint = 'https://oauth.overdrive.com/token';
my $oauth_only; 
my ($patron_auth, $barcode, $password, $websiteid, $authorizationname); 
my ($verbose, $help);
my ($authtoken, $auth_content);

GetOptions(
    'account=s'        => \$account_id,     # OverDrive API account ID
    'get-token'        => \$get_token,      # generate basic client token
    'key=s'            => \$client_key,     # OverDrive client key
    'secret=s'         => \$client_secret,  # OverDrive client secret
    'token=s'          => \$basic_token,    # basic client token for OAuth requests
    'endpoint=s'       => \$api_endpoint,   # main API endpoint
    'content=s'        => \$content,        # main request content (optional)
    'oauth-endpoint=s' => \$oauth_endpoint, # API endpoint for OAuth requests
    'oauth-only'       => \$oauth_only,     # only attempt OAuth request, then stop
    'patron-auth'      => \$patron_auth,    # perform patron authentication
    'barcode=s'        => \$barcode,        # patron barcode
    'password=s'       => \$password,        # patron password
    'websiteid=s'      => \$websiteid,      # OverDrive website ID
    'authorizationname=s' => \$authorizationname, # OverDrive ILS name
    'verbose'          => \$verbose,        # verbose output
    'help'             => \$help            # show help message and exit
);

if ($help) {
    print <<"HELP";
USAGE:
    $0 --get-token --key <client-key> --secret <client-secret>
    $0 --account <account_id> --token <basic_token> [ --endpoint https://api.overdrive.com/v1/libraries/1234 [ --content <content> ] ]
    $0 --account <account_id> --token <basic_token> --oauth-only
    $0 --account <account_id> --token <basic_token> --patron-auth [ --endpoint https://oauth-patron.overdrive.com/patrontoken ] --barcode <barcode> [ --password <password> ] --websiteid <websiteid> --authorizationname <authorizationname>

OPTIONS:
    --get-token
        Generate OverDrive API basic token.
    --key
        Client key supplied by OverDrive.  Required with --get-token.
    --secret
        Client secret supplied by OverDrive.  Required with --get-token.
    --token
        Your OverDrive API basic token (clientKey:clientSecret, Base64-encoded).
        Required unless using --get-token.
    --account
        Your OverDrive API account ID (e.g. 1234).  Not required for generating
        a basic token; required for everything else.
    --oauth-endpoint
        OverDrive API endpoint for OAuth token requests.
        Default: https://oauth.overdrive.com/token.
    --endpoint
        OverDrive API endpoint that you wish to test.
        Default: https://api.overdrive.com/v1/libraries/<account>
    --content
        JSON content of main API request.  Required only if you have specified
        an endpoint that expects JSON message content.
    --oauth-only
        Only request an OAuth token; do not attempt further API requests.
    --patron-auth
        Submit a patron authentication request.
    --barcode
        Patron barcode.  Required with --patron-auth.
    --password
        Patron password.  Required with --patron-auth if your library requires
        password for patron authentication.
    --websiteid
        Website ID supplied by OverDrive.  Required with --patron-auth.
    --authorizationname
        ILS name supplied by OverDrive.  Required with --patron-auth.
    --verbose
        Print full HTTP requests and responses.
    --help
        Print this help message.

EXAMPLES:

    To generate your basic token, given a client key and client secret supplied
    by OverDrive:

    $0 --get-token --key <client-key> --secret <client-secret>

    To send a basic API request (this is useful for validating your client
    credentials and determining whether the OverDrive API is currently
    available):

    $0 --account <account_id> --token <basic_token>

    To send a request to a specific API endpoint:

    $0 --account <account_id> --token <basic_token> \
    --endpoint <endpoint> --content <content>

    To test OverDrive API authentication for a specific patron:

    $0 --account <account_id> --token <basic_token> \
    --patron-auth --barcode <barcode> --password <password> \
    --websiteid <websiteid> --authorizationname <authorizationname>

HELP
    exit;
}

if ($get_token) {
    die "No client key provided" unless ($client_key);
    die "No client secret provided" unless ($client_secret);
    $basic_token = encode_base64("$client_key:$client_secret");
    print "Your basic token is: $basic_token\n";
    exit unless ($api_endpoint || $oauth_only || $patron_auth);
}

die "No basic token provided" unless ($basic_token);
die "No account ID provided" unless ($account_id);

my $ua = new LWP::UserAgent;

# First, we use our basic token to request an access (bearer) token from the OAuth endpoint.

if (!$patron_auth) {

    # construct the HTTP request
    my $auth_req = HTTP::Request->new( POST => $oauth_endpoint );
    $auth_req->header('Authorization' => "Basic $basic_token");
    $auth_req->content_type('application/x-www-form-urlencoded;charset=UTF-8');
    $auth_req->content('grant_type=client_credentials');

    # send the request and handle the response
    my $auth_resp = $ua->request($auth_req);
    if (!$auth_resp->is_success) {
        die "Error on auth request: " . $auth_resp->status_line . "\n";
    }
    $auth_content = decode_json($auth_resp->decoded_content);
    $authtoken = $auth_content->{access_token};

    print "$authtoken\n" if ($oauth_only || $verbose);
    exit if ($oauth_only);
    sleep 1;
}

# Now that we have our bearer token, we can make our main API request.
if (!$api_endpoint) {
    if ($patron_auth) {
        $api_endpoint = "https://oauth-patron.overdrive.com/patrontoken";
    } else {
        $api_endpoint = "https://api.overdrive.com/v1/libraries/$account_id";
    }
}

# Determine method and initialize HTTP request object
my $method = ($patron_auth) ? 'POST' : 'GET';
my $api_req = HTTP::Request->new( $method => $api_endpoint );

# Flesh out our request.
if ($patron_auth) {
    $api_req->header('Authorization' => "Basic $basic_token");
    $api_req->content_type("application/x-www-form-urlencoded;charset=UTF-8");
    if ($password) {
        $api_req->content("grant_type=password&username=$barcode&password=$password&scope=websiteid:$websiteid authorizationname:$authorizationname");
    } else {
        $api_req->content("grant_type=password&username=$barcode&password=1234&password_required=false&scope=websiteid:$websiteid authorizationname:$authorizationname");
    }
} else {
    $api_req->header('Authorization' => "bearer $authtoken");
    $api_req->content_type('application/json');
    $api_req->content($content) if ($content);
}
print Dumper $api_req if ($verbose);

# Send API request and handle response.
my $api_resp = $ua->request($api_req);
if (!$api_resp->is_success) {
    print "Error on API request: " . $api_resp->status_line . "\n";
    print Dumper $api_resp if ($verbose);
    die;
}
print "Success: " . $api_resp->status_line . "\n";
print $api_resp->decoded_content . "\n" if ($verbose);

