package OpenILS::WWW::EGCatLoader;

use strict; use warnings;
use Apache2::Const -compile => qw(HTTP_BAD_REQUEST);
use HTTP::Async;
use HTTP::Request;
use XML::Simple;

my $U = 'OpenILS::Application::AppUtils';

use constant OA_API_AUTH_TYPE => 'OAApiKey';
use constant OA_API_WAIT_SECONDS => 2;
use constant OA_ATTR_PREFIX => 'prefix';
use constant OA_ATTR_FIRST_GIVEN_NAME => 'first_given_name';
use constant OA_ATTR_SECOND_GIVEN_NAME => 'second_given_name';
use constant OA_ATTR_FAMILY_NAME => 'family_name';
use constant OA_ATTR_SUFFIX => 'suffix';
use constant OA_ATTR_EMAIL => 'email';
use constant OA_ATTR_HOME_OU => 'home_ou';
use constant OA_SIGNOUT_URL => 'https://login.openathens.net/signout';
use constant OA_SESSION_REQUEST_TYPE =>
    'application/vnd.eduserv.iam.auth.localAccountSessionRequest+json';

my @oa_config_fields = qw/active api_key connection_id connection_uri
    auto_signon_enabled auto_signout_enabled release_prefix
    release_first_given_name release_second_given_name release_family_name
    release_suffix release_email release_home_ou/;


# -----------------------------------------------------------------------------
# If sign in to OpenAthens is enabled, redirects to the local OpenAthens
# sign-in handler, including the original redirect as a parameter.
# -----------------------------------------------------------------------------
sub perform_openathens_sso_if_required {
    my ($self, $auth_response, $redirect_to, $cookie_list) = @_;
    my $ctx = $self->ctx;
    my $e = $self->editor;

    # Don't generate a new redirect to the OpenAthens handler if that's where
    # we came from.
    if (index(
        $redirect_to,
        $ctx->{opac_root} . '/sso/openathens'
    ) == 0) {
        return;
    }

    # Use the auth_token to establish the context user and load the relevant
    # OpenAthens config. This is needed because the OpenAthens behaviour
    # depends on the org unit, but the user context has not yet been loaded.
    if ($e->authtoken($auth_response->{payload}->{authtoken})
        && $e->checkauth
    ) {
        $ctx->{user} = $e->requestor;
    }

    return unless $ctx->{user};

    my $openathens_config =
        $self->_get_openathens_config_for_org($ctx->{user}->home_ou);

    if ($openathens_config
        && $U->is_true($openathens_config->{active})
        && $U->is_true($openathens_config->{auto_signon_enabled})
    ) {
        # Remove scheme and hostname from redirect_to (this may have been set
        # by the login form, but isn't allowed by the OpenAthens SSO page)
        if ($redirect_to =~ m#^https?://\Q$ctx->{hostname}\E(.+)#) {
            $redirect_to = $1;
        }

        my $redirect = $ctx->{opac_root} . '/sso/openathens?redirect_to='
            . uri_escape_utf8($redirect_to);

        if ($redirect) {
            return $self->generic_redirect($redirect, $cookie_list);
        }
    }
}

# -----------------------------------------------------------------------------
# If sign out of OpenAthens is enabled, redirects to the local OpenAthens
# sign-out handler, including the original redirect as a parameter.
# -----------------------------------------------------------------------------
sub perform_openathens_signout_if_required {
    my ($self, $redirect_to, $cookie_list) = @_;
    my $ctx = $self->ctx;

    return unless $ctx->{user};

    my $openathens_config =
        $self->_get_openathens_config_for_org($ctx->{user}->home_ou);

    if ($openathens_config
        && $U->is_true($openathens_config->{active})
        && $U->is_true($openathens_config->{auto_signout_enabled})
    ) {
        my $redirect = $ctx->{opac_root}
            . '/sso/openathens/logout?redirect_to='
            . uri_escape_utf8($redirect_to);

        if ($redirect) {
            return $self->generic_redirect($redirect, $cookie_list);
        }
    }

    return undef;
}

# -----------------------------------------------------------------------------
# Handler for /eg/opac/sso/openathens. Establishes single-sign-on session on 
# OpenAthens, if configured. Implements
# http://docs.openathens.net/display/public/MD/Implementing+the+API+connector+in+your+code
#
# There are two flows supported:
#
# 1. The user just logged in locally, and we want to sign them on to
# OpenAthens as well (if this feature is enabled for the user's org unit).
#
# In this case 'redirect_to' will be set and will be the local URL that
# initiated login, e.g. /eg/opac/myopac/main. We will send the user to
# OpenAthens with a token that will establish their sign-on session, and with a
# redirect parameter instructing OpenAthens to send them back to the original
# local URL afterwards.
#
# 2. The user tried to access an OpenAthens-protected resource and chose to
# sign on via their account with us.
#
# In this case, 'returnData' will be supplied by OpenAthens and is opaque to
# us. We will send the user back to OpenAthens with a token that will
# establish their sign-on session, together with the returnData. OpenAthens
# can then forward the user on to whichever resource they were originally
# requesting.
# -----------------------------------------------------------------------------
sub load_openathens_sso {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;

    my $redirect_to = $cgi->param('redirect_to') || '';
    my $return_data = $cgi->param('returnData') || '';
    my $status = $cgi->param('status') || '';

    # 'redirect_to' must be empty or a local URL
    return Apache2::Const::HTTP_BAD_REQUEST unless $redirect_to =~ m:^($|/):;

    # 'redirect_to' and 'returnData' are mutually exclusive
    return Apache2::Const::HTTP_BAD_REQUEST if ($redirect_to && $return_data);

    my $openathens_config =
        $self->_get_openathens_config_for_org($ctx->{user}->home_ou);

    if (!$openathens_config
        || !$U->is_true($openathens_config->{active})
    ) {
        return $self->generic_redirect();
    }

    if ($redirect_to) {
        # OpenAthens sign-on has been initiated by local login.

        if ($status) {
            # User has already been redirected to OpenAthens and back again.
            # Status will indicate success/failure, but ignore: we don't want
            # to show the user any errors because it's a non-interactive flow.
            return $self->generic_redirect($redirect_to);
        } else {
            # Request has not yet gone to OpenAthens; initiate now by making
            # API call then redirecting.
            my $return_url = $ctx->{proto} . '://' . $ctx->{hostname}
                . $ctx->{opac_root} . '/sso/openathens?redirect_to='
                . uri_escape_utf8($redirect_to);

            my $oa_redirect = $self->_get_openathens_session_initiator_url(
                $return_url
            );

            return $self->generic_redirect($oa_redirect);
        }
    } elsif ($return_data) {
        # OpenAthens has initiaited sign-on; make API call using supplied data,
        # then redirect back.
        my $oa_redirect = $self->_get_openathens_session_initiator_url(
            undef,
            $return_data
        );

        return $self->generic_redirect($oa_redirect);
    } else {
        # Page called with no relevant parameters; go to home.
        return $self->generic_redirect();
    }
}

# -----------------------------------------------------------------------------
# Hanlder for /eg/opac/sso/openathens/logout. Ends OpenAthens session.
# Optionally called after local logout.
# -----------------------------------------------------------------------------
sub load_openathens_logout {
    my $self = shift;
    my $ctx = $self->ctx;

    $self->generic_redirect(OA_SIGNOUT_URL);
}

# -----------------------------------------------------------------------------
# Retrieves the relevant OpenAthens config for the given org unit. If not set,
# searches up the org hierarchy to find one, or returns undef. If an org unit
# has multiple configs, only the first is used.
# -----------------------------------------------------------------------------
sub _get_openathens_config_for_org {
    my ($self, $org_id) = @_;
    my $e = new_editor();

    my $parent_org = $U->get_org_unit_parent($org_id);

    my $configs = $e->json_query({
        select => {
            coai => \@oa_config_fields,
            coauf => [
                { column => 'name', alias => 'id_field' }
            ],
            coanf => [
                { column => 'name', alias => 'dn_field' }
            ]
        },
        from => {
            coai => {
                coauf => {},
                coanf => {}
            }
        },
        where => {
            '+coai' => { org_unit => $org_id }
        },
        order_by => { 'coai' => ['id'] }
    });

    if (@$configs) {
        return $configs->[0];
    } elsif ($parent_org) {
        return $self->_get_openathens_config_for_org($parent_org);
    } else {
        return undef;
    }
}

# -----------------------------------------------------------------------------
# Makes POST to OpenAthens local-auth API. Returns URL to which the user should
# be redirected to establish OpenAthens SSO session.
# -----------------------------------------------------------------------------
sub _get_openathens_session_initiator_url {
    my $self = shift;
    my ($return_url, $return_data) = @_;
    my $ctx = $self->ctx;
    my $user = $ctx->{user};

    my $openathens_config =
        $self->_get_openathens_config_for_org($user->home_ou);

    # must have either returnUrl or returnData but not both
    return undef if $return_url && $return_data;
    return undef if !$return_url && !$return_data;

    # Select the chosen unique identifier attribute
    my $unique_user_identifier;
    if ($openathens_config->{id_field} eq 'id') {
        $unique_user_identifier = $user->id;
    } elsif ($openathens_config->{id_field} eq 'usrname') {
        $unique_user_identifier = $user->usrname;
    }

    # Select the chosen display name attribute
    my $display_name;
    if ($openathens_config->{dn_field} eq 'id') {
        $display_name = $user->id;
    } elsif ($openathens_config->{dn_field} eq 'usrname') {
        $display_name = $user->usrname;
    } elsif ($openathens_config->{dn_field} eq 'fullname') {
        $display_name =
            ($user->pref_first_given_name || $user->first_given_name)
                . ' ' . ($user->pref_family_name || $user->family_name);
    }

    # Build object to POST to OpenAthens
    my $request_obj = {
        'connectionID' => $openathens_config->{connection_id},
        'uniqueUserIdentifier' => $unique_user_identifier,
        'displayName' => $display_name,
        'attributes' => {}
    };

    # Optional attributes
    if ($U->is_true($openathens_config->{release_prefix})) {
        $request_obj->{attributes}->{OA_ATTR_PREFIX} = $user->prefix;
    }

    if ($U->is_true($openathens_config->{release_first_given_name})) {
        $request_obj->{attributes}->{OA_ATTR_FIRST_GIVEN_NAME} =
            $user->pref_first_given_name || $user->first_given_name;
    }

    if ($U->is_true($openathens_config->{release_second_given_name})) {
        $request_obj->{attributes}->{OA_ATTR_SECOND_GIVEN_NAME} =
            $user->pref_second_given_name || $user->second_given_name;
    }

    if ($U->is_true($openathens_config->{release_family_name})) {
        $request_obj->{attributes}->{OA_ATTR_FAMILY_NAME} =
            $user->pref_family_name || $user->family_name;
    }

    if ($U->is_true($openathens_config->{release_suffix})) {
        $request_obj->{attributes}->{OA_ATTR_SUFFIX} = $user->suffix;
    }

    if ($U->is_true($openathens_config->{release_email})) {
        $request_obj->{attributes}->{OA_ATTR_EMAIL} = $user->email;
    }

    my $ou_id = $user->home_ou;
    if ($ou_id && $U->is_true($openathens_config->{release_home_ou})) {
        my $ou = $ctx->{get_aou}->($ou_id);
        if ($ou) {
            $request_obj->{attributes}->{OA_ATTR_HOME_OU} = $ou->shortname;
        }
    }

    if ($return_url) {
        $request_obj->{returnUrl} = $return_url;
    } elsif ($return_data) {
        $request_obj->{returnData} = $return_data;
    }

    # Execute OpenAthens API request
    my $auth_header = OA_API_AUTH_TYPE . ' ' . $openathens_config->{api_key};
    my $body = JSON::XS->new->utf8->encode($request_obj);
    my $async = HTTP::Async->new;
    $async->add(HTTP::Request->new(
        'POST',
        $openathens_config->{connection_uri},
        [
            'Authorization' => $auth_header,
            'Content-type' => OA_SESSION_REQUEST_TYPE
        ],
        $body
    ));

    my $response = $async->wait_for_next_response(OA_API_WAIT_SECONDS);
    if ($response->is_error) {
        $self->apache->log->error('Error POSTing to OpenAthens API: '
            . $response->code . ' ' . $response->message);

        return undef;
    }

    # JSON response should contain the sessionInitiatorUrl
    my $response_obj = JSON::XS->new->utf8->decode($response->content);
    my $session_initiator_url = $response_obj->{sessionInitiatorUrl};
    if (!$session_initiator_url) {
        $self->apache->log->error(
            'No sessionInitiatorUrl included in response from OpenAthens');

        return undef;
    }

    return $session_initiator_url;
}

1;
