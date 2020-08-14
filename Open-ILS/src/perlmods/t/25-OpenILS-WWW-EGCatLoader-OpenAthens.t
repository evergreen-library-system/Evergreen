#!perl -T

# -----------------------------------------------------------------------------
# Unit tests for OpenILS::WWW::EGCatLoader::OpenAthens
# -----------------------------------------------------------------------------
#
# These are strict unit tests of this module in isolation. Lower layers are
# mocked:
#
# * The Evergreen context is mocked to provide a dummy base URL etc.
# * Apache is mocked to capture redirects being generated
# * CGI is mocked to simulate query string input
# * HTTP:Request is mocked to capture requests that would be sent to the
#   OpenAthens API
# * HTTP:Async is mocked to simulate a response from the OpenAthens API
#
# -----------------------------------------------------------------------------

use strict;
use Test::MockModule;
use Test::MockObject;
use Test::More tests => 35;
use OpenILS::WWW::EGCatLoader;

use constant OA_SIGNOUT_URL => qr/https:\/\/login\.openathens\.net\/signout/;

BEGIN {
	use_ok('OpenILS::WWW::EGCatLoader::OpenAthens');
}

# set up an arbitrary global context
my $ctx = {
    proto => 'https',
    hostname => 'test.org',
    opac_root => '/mytesteg/opac',
    home_page => '/mytesteg/opac/home'
};

# capture output printed to Apache
my $apache_capture;
my $apache = Test::MockObject->new()
    ->mock(print => sub {
        $apache_capture = @_[1];
    });

# -----------------------------------------------------------------------------
# method under test:    perform_openathens_sso_if_required
#
# test case:            patron is not logged in
#
# expected outcome:     does nothing
# -----------------------------------------------------------------------------
{
    my $auth_response = {};
    my $redirect_to = '/mytesteg/opac/home';
    $apache_capture = undef;

    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    $mut->perform_openathens_sso_if_required($auth_response, $redirect_to);
    
    is($apache_capture, undef, 'OpenAthens: no patron: no redirect');
}

# -----------------------------------------------------------------------------
# method under test:    perform_openathens_sso_if_required
#
# test case:            patron is logged in but home OU is not configured for
#                       OpenAthens
#
# expected outcome:     does nothing
# -----------------------------------------------------------------------------
{
    my $patron = Test::MockObject->new()
        ->mock(home_ou => sub { return 123; });

    my $editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
        ->redefine(authtoken => 1)
        ->redefine(checkauth => 1)
        ->redefine(requestor => $patron)
        ->redefine(json_query => [ ]);

    my $utils = Test::MockModule->new('OpenILS::Application::AppUtils')
        ->redefine(get_org_unit_parent => undef);

    my $auth_response = { payload => { auth_token => 'abc123' } };
    my $redirect_to = '/mytesteg/opac/home';
    $apache_capture = undef;

    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    $mut->perform_openathens_sso_if_required($auth_response, $redirect_to);

    is($apache_capture, undef, 'OpenAthens: no OA config: no redirect');
}

# -----------------------------------------------------------------------------
# method under test:    perform_openathens_sso_if_required
#
# test case:            patron is logged in and their home OU is configured
#                       to sign in to OpenAthens automatically when logging
#                       in to Evergreen
#
# expected outcome:     issues a redirect to our local OpenAthens sign-on
#                       handler at <OPAC_ROOT>/sso/openathens
# -----------------------------------------------------------------------------
{
    my $patron = Test::MockObject->new()
        ->mock(home_ou => sub { return 123; });

    my $oa_config = {
        active => 1,
        auto_signon_enabled => 1
    };

    my $editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
        ->redefine(authtoken => 1)
        ->redefine(checkauth => 1)
        ->redefine(requestor => $patron)
        ->redefine(json_query => [ $oa_config ]);

    my $utils = Test::MockModule->new('OpenILS::Application::AppUtils')
        ->redefine(get_org_unit_parent => undef);

    my $auth_response = { payload => { auth_token => 'abc123' } };
    my $redirect_to = '/mytesteg/opac/home';

    $apache_capture = undef;
    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    my $result =
        $mut->perform_openathens_sso_if_required($auth_response, $redirect_to);

    my $expected_path = qr/$ctx->{opac_root}\/sso\/openathens/;
    my $expected_redirect = qr/%2Fmytesteg%2Fopac%2Fhome/;
    is($result, Apache2::Const::REDIRECT, 'OpenAthens: login: redirects');
    like($apache_capture, qr/Status: 302/, 'OpenAthens: login: issues 302');
    like(
        $apache_capture,
        qr/Location: ${expected_path}\?redirect_to=${$expected_redirect}/,
        'OpenAthens: login: correct URL'
    );
}

# -----------------------------------------------------------------------------
# method under test:    perform_openathens_sso_if_required
#
# test case:            login has been initiated from an incoming request via
#                       the OpenAthens handler
#
# expected outcome:     does not issue a new redirect, otherwise it would cause
#                       a redirect loop
{
    my $patron = Test::MockObject->new()
        ->mock(home_ou => sub { return 123; });

    my $oa_config = {
        active => 1,
        auto_signon_enabled => 1
    };

    my $editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
        ->redefine(authtoken => 1)
        ->redefine(checkauth => 1)
        ->redefine(requestor => $patron)
        ->redefine(json_query => [ $oa_config ]);

    my $utils = Test::MockModule->new('OpenILS::Application::AppUtils')
        ->redefine(get_org_unit_parent => undef);

    my $auth_response = { payload => { auth_token => 'abc123' } };
    my $redirect_to = '/mytesteg/opac/sso/openathens?returnData=37580gwev';

    $apache_capture = undef;
    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    my $result =
        $mut->perform_openathens_sso_if_required($auth_response, $redirect_to);

    is($apache_capture, undef, 'OpenAthens: login: no redirect loop');
}

# -----------------------------------------------------------------------------
# method under test:    perform_openathens_signout_if_required
#
# test case:            patron is not logged in
#
# expected outcome:     does nothing
# -----------------------------------------------------------------------------
{
    my $redirect_to = '/mytesteg/opac/home';
    $apache_capture = undef;

    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    $mut->perform_openathens_signout_if_required($redirect_to);
    
    is($apache_capture, undef, 'OpenAthens: logout, no patron: no redirect');
}

# -----------------------------------------------------------------------------
# method under test:    perform_openathens_signout_if_required
#
# test case:            patron is logged in but home OU is not configured for
#                       OpenAthens
#
# expected outcome:     does nothing
# -----------------------------------------------------------------------------
{
    my $patron = Test::MockObject->new()
        ->mock(home_ou => sub { return 123; });

    $ctx->{user} = $patron;

    my $editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
        ->redefine(json_query => [ ]);

    my $utils = Test::MockModule->new('OpenILS::Application::AppUtils')
        ->redefine(get_org_unit_parent => undef);

    my $redirect_to = '/mytesteg/opac/home';
    $apache_capture = undef;

    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    $mut->perform_openathens_signout_if_required($redirect_to);

    is($apache_capture, undef, 'OpenAthens: logout no OA config: no redirect');
}

# -----------------------------------------------------------------------------
# method under test:    perform_openathens_signout_if_required
#
# test case:            patron is logged in and their home OU is configured
#                       to sign out of OpenAthens automatically when logging
#                       out of Evergreen
#
# expected outcome:     issues a redirect to our local OpenAthens sign-out
#                       handler at <OPAC_ROOT>/sso/openathens/logout
# -----------------------------------------------------------------------------
{
    my $patron = Test::MockObject->new()
        ->mock(home_ou => sub { return 123; });

    my $oa_config = {
        active => 1,
        auto_signout_enabled => 1
    };

    $ctx->{user} = $patron;

    my $editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
        ->redefine(json_query => [ $oa_config ]);

    my $utils = Test::MockModule->new('OpenILS::Application::AppUtils')
        ->redefine(get_org_unit_parent => undef);

    my $redirect_to = '/mytesteg/opac/home';

    $apache_capture = undef;
    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    my $result =
        $mut->perform_openathens_signout_if_required($redirect_to);

    my $expected_path = qr/$ctx->{opac_root}\/sso\/openathens\/logout/;
    my $expected_redirect = qr/%2Fmytesteg%2Fopac%2Fhome/;
    is($result, Apache2::Const::REDIRECT, 'OpenAthens: logout: redirects');
    like($apache_capture, qr/Status: 302/, 'OpenAthens: logout: issues 302');
    like(
        $apache_capture,
        qr/Location: ${expected_path}\?redirect_to=${$expected_redirect}/,
        'OpenAthens: logout: correct URL'
    );
}

# -----------------------------------------------------------------------------
# method under test:    load_openathens_sso - for OPAC_HOME/sso/openathens
#
# test case:            1) initiated by Evergreen - ?redirect_to= is present
#
# expected outcome:     queries the OpenAthens API to obtain a unique session
#                       creation URL for the logged in patron, then issues a
#                       redirect to that URL
# -----------------------------------------------------------------------------
{
    my $patron = Test::MockObject->new()
        ->mock(id => sub { return 42; })
        ->mock(home_ou => sub { return 123; });

    my $api_endpoint = 'https://login.openathens.net/api/etc';
    my $oa_config = {
        active => 1,
        auto_signon_enabled => 1,
        id_field => 'id',
        dn_field => 'id',
        connection_uri => $api_endpoint,
        connection_id => '123456',
        api_key => 'abc123'
    };

    $ctx->{user} = $patron;

    my $editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
        ->redefine(json_query => [ $oa_config ]);

    my $utils = Test::MockModule->new('OpenILS::Application::AppUtils')
        ->redefine(get_org_unit_parent => undef);

    # mock the query string
    my $redirect_to = '/mytesteg/opac/home';
    my $cgi = Test::MockModule->new('CGI')
        ->redefine(param => sub {
            my $key = @_[1];
            return $redirect_to if ($key eq 'redirect_to');
            return undef;
        });

    # the object we expect to be posted to the OpenAthens API
    my $expected_api_request = {
        connectionID => '123456',
        uniqueUserIdentifier => 42,
        displayName => 42,
        attributes => {},
        returnUrl => 'https://test.org/mytesteg/opac/sso/openathens'
            . '?redirect_to=%2Fmytesteg%2Fopac%2Fhome'
    };

    # create a mock OpenAthens API JSON response
    my $sso_url = 'https://login.openathens.net/account/sso?t=eyj0e';
    my $openathens_response_body = "{\"sessionInitiatorUrl\":\"$sso_url\"}";
    my $openathens_response = Test::MockObject->new()
        ->mock(is_error => sub { return 0; })
        ->mock(content => sub { return $openathens_response_body; });

    # mock the web request to the API
    my $http_request_capture;
    my $async = Test::MockModule->new('HTTP::Async')
        ->redefine(add => sub {
            # capture the HTTP request that is built, to check later
            $http_request_capture = @_[1];
        })
        # mock the async behaviour to return our mocked response
        # without using the network
        ->redefine(wait_for_next_response => $openathens_response);

    $apache_capture = undef;
    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    my $result = $mut->load_openathens_sso();

    # check the API HTTP request that was built
    my $method = $http_request_capture->method;
    my $uri = $http_request_capture->uri;
    my $auth_header = $http_request_capture->header('Authorization');
    my $content_type = $http_request_capture->header('Content-type');
    my $content = JSON::XS->new->utf8->decode($http_request_capture->content);
    my $expected_content_type
        = 'application/vnd.eduserv.iam.auth.localAccountSessionRequest+json';
    is($method, 'POST', 'OpenAthens: SSO 1: uses POST to API');
    is($uri, $api_endpoint, 'OpenAthens: SSO 1: posts to correct URI');
    is($auth_header, 'OAApiKey abc123', 'OpenAthens: SSO 1: uses API key');
    is($content_type, $expected_content_type, 'OpenAthens: SSO 1: type ok');
    is_deeply($content, $expected_api_request, 'OpenAthens: SSO 1: data ok');

    # check the resulting redirect
    my $expected_redirect
        = qr/https:\/\/login\.openathens\.net\/account\/sso\?t=eyj0e/;
    is($result, Apache2::Const::REDIRECT, 'OpenAthens: SSO 1: redirects');
    like($apache_capture, qr/Status: 302/, 'OpenAthens: SSO 1: issues 302');
    like($apache_capture, $expected_redirect, 'OpenAthens: SSO 1: URL ok');
}

# -----------------------------------------------------------------------------
# method under test:    load_openathens_sso - for OPAC_HOME/sso/openathens
#
# test case:            2) initiated by OpenAthens - ?returnData= is present
#
# expected outcome:     queries the OpenAthens API to obtain a unique session
#                       creation URL for the logged in patron, then issues a
#                       redirect to that URL
# -----------------------------------------------------------------------------
{
    my $patron = Test::MockObject->new()
        ->mock(id => sub { return 42; })
        ->mock(home_ou => sub { return 123; });

    my $api_endpoint = 'https://login.openathens.net/api/etc';
    my $oa_config = {
        active => 1,
        auto_signon_enabled => 1,
        id_field => 'id',
        dn_field => 'id',
        connection_uri => $api_endpoint,
        connection_id => '123456',
        api_key => 'abc123'
    };

    $ctx->{user} = $patron;

    my $editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
        ->redefine(json_query => [ $oa_config ]);

    my $utils = Test::MockModule->new('OpenILS::Application::AppUtils')
        ->redefine(get_org_unit_parent => undef);

    # mock the query string
    my $return_data = 'jk46gubeuvpweb';
    my $cgi = Test::MockModule->new('CGI')
        ->redefine(param => sub {
            my $key = @_[1];
            return $return_data if ($key eq 'returnData');
            return undef;
        });

    # the object we expect to be posted to the OpenAthens API
    my $expected_api_request = {
        connectionID => '123456',
        uniqueUserIdentifier => 42,
        displayName => 42,
        attributes => {},
        returnData => 'jk46gubeuvpweb'
    };

    # create a mock OpenAthens API JSON response
    my $sso_url = 'https://login.openathens.net/account/sso?t=eyj0e';
    my $openathens_response_body = "{\"sessionInitiatorUrl\":\"$sso_url\"}";
    my $openathens_response = Test::MockObject->new()
        ->mock(is_error => sub { return 0; })
        ->mock(content => sub { return $openathens_response_body; });

    # mock the web request to the API
    my $http_request_capture;
    my $async = Test::MockModule->new('HTTP::Async')
        ->redefine(add => sub {
            # capture the HTTP request that is built, to check later
            $http_request_capture = @_[1];
        })
        # mock the async behaviour to return our mocked response
        # without using the network
        ->redefine(wait_for_next_response => $openathens_response);

    $apache_capture = undef;
    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    my $result = $mut->load_openathens_sso();

    # check the API HTTP request that was built
    my $method = $http_request_capture->method;
    my $uri = $http_request_capture->uri;
    my $auth_header = $http_request_capture->header('Authorization');
    my $content_type = $http_request_capture->header('Content-type');
    my $content = JSON::XS->new->utf8->decode($http_request_capture->content);
    my $expected_content_type
        = 'application/vnd.eduserv.iam.auth.localAccountSessionRequest+json';
    is($method, 'POST', 'OpenAthens: SSO 2: uses POST to API');
    is($uri, $api_endpoint, 'OpenAthens: SSO 2: posts to correct URI');
    is($auth_header, 'OAApiKey abc123', 'OpenAthens: SSO 2: uses API key');
    is($content_type, $expected_content_type, 'OpenAthens: SSO 2: type ok');
    is_deeply($content, $expected_api_request, 'OpenAthens: SSO 2: data ok');

    # check the resulting redirect
    my $expected_redirect
        = qr/https:\/\/login\.openathens\.net\/account\/sso\?t=eyj0e/;
    is($result, Apache2::Const::REDIRECT, 'OpenAthens: SSO 2: redirects');
    like($apache_capture, qr/Status: 302/, 'OpenAthens: SSO 2: issues 302');
    like($apache_capture, $expected_redirect, 'OpenAthens: SSO 2: URL ok');
}

# -----------------------------------------------------------------------------
# method under test:    load_openathens_sso - for OPAC_HOME/sso/openathens
#
# test case:            3) both ?redirect_to and ?returnData= are present
#
# expected outcome:     returns 400 status
# -----------------------------------------------------------------------------
{
    # mock the query string
    my $redirect_to = '/mytesteg/opac/home';
    my $return_data = 'jk46gubeuvpweb';
    my $cgi = Test::MockModule->new('CGI')
        ->redefine(param => sub {
            my $key = @_[1];
            return $redirect_to if ($key eq 'redirect_to');
            return $return_data if ($key eq 'returnData');
            return undef;
        });

    $apache_capture = undef;
    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    my $result = $mut->load_openathens_sso();

    is($result, Apache2::Const::HTTP_BAD_REQUEST, 'OpenAthens: SSO 3: badreq');
}

# -----------------------------------------------------------------------------
# method under test:    load_openathens_sso - for OPAC_HOME/sso/openathens
#
# test case:            4) neither ?redirect_to or ?returnData= are present
#
# expected outcome:     redirects to OPAC home
# -----------------------------------------------------------------------------
{
    # mock the empty query string
    my $cgi = Test::MockModule->new('CGI')
        ->redefine(param => sub {
            return undef;
        });

    $apache_capture = undef;
    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    my $result = $mut->load_openathens_sso();

    is($result, Apache2::Const::REDIRECT, 'OpenAthens: SSO 4: redirects');
    like($apache_capture, qr/Status: 302/, 'OpenAthens: SSO 4: issues 302');
    like(
        $apache_capture,
        qr/Location: \/mytesteg\/opac\/home/,
        'OpenAthens: SSO 4: redirects to OPAC home'
    );
}

# -----------------------------------------------------------------------------
# method under test:    load_openathens_logout
#
# expected outcome:     Issues a redirect to the OpenAthens sign-out URL.
# -----------------------------------------------------------------------------
{
    my $mut = OpenILS::WWW::EGCatLoader->new($apache, { %$ctx });
    my $result = $mut->load_openathens_logout;

    is($result, Apache2::Const::REDIRECT, 'OpenAthens: logout: redirects');
    like($apache_capture, qr/Status: 302/, 'OpenAthens: logout: issues 302');
    like($apache_capture, OA_SIGNOUT_URL, 'OpenAthens: logout: correct URL');
}
