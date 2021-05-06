# -----------------------------------------------------------------------------
# Submodule for handling patron sign-in and sign-out of the OpenAthens service
# -----------------------------------------------------------------------------

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
# sub perform_openathens_sso_if_required
# -----------------------------------------------------------------------------
#
# This method is called by EGCatLoader as part of the patron login process. It
# is called after the login credentials have been checked, but before the
# patron is redirected back to the page they originally requested.
#
# If the patron's home library is configured to sign patrons in to OpenAthens
# automatically when they log in to Evergreen, then this method issues a
# redirect to the OpenAthens sign-in handler at <OPAC_ROOT>/sso/openathens,
# which is responsible for establishing an OpenAthens user session. The
# ?redirect_to query string parameter is passed forward to the OpenAthens
# sign-in handler so that it can in turn issue a redirect back to the
# originally requested page once it has done its work.
#
# If the home library is not configured for automatic OpenAthens sign-in, this
# method does nothing, and leaves the rest of EGCatLoader to complete its
# normal redirect back to the originally requested page.
#
# In the case where a patron who is not already logged in has arrived at the
# OpenAthens sign-in handler from an external website, EGCatLoader will ask
# them to log in, and this method will be called as a result. In this case we
# don't construct a new redirect to the OpenAthens handler with a &redirect_to
# parameter, otherwise we could cause a redirect loop. We just leave
# EGCatLoader to complete its normal redirect back to the originally requested
# page after login. (We can identify this case by ?redirect_to matching the URL
# of the OpenAthens handler.) The flow that occurs in this case is described in
# more detail in the comment on sub load_openathens_sso, case 2.
#
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
# sub perform_openathens_signout_if_required
# -----------------------------------------------------------------------------
#
# This method is called by EGCatLoader as part of the patron logout process. It
# is called while the patron's identity is still in session as $ctx->{user},
# and before the patron is redirected back to the home page.
#
# If the patron's home library is configured to sign patrons out of OpenAthens
# when they log out of Evergreen, then this method issues a redirect to the
# OpenAthens sign-out handler at <OPAC_ROOT>/sso/openathens/logout, which is
# responsible for destroying the OpenAthens session. The redirect_to parameter
# (usually set to the home page when logging out) is passed forward to the
# OpenAthens sign-out handler so that it can in turn issue a redirect back to
# home page once it has done its work.
#
# If the home library is not configured for OpenAthens sign-out, this method
# does nothing, and leaves the rest of EGCatLoader to complete its normal
# redirect back to the home page.
#
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
# sub load_openathens_sso
# -----------------------------------------------------------------------------
#
# This is the handler for <OPAC_ROOT>/sso/openathens. Its job is to establish a
# single-sign-on (SSO) session on OpenAthens for an Evergreen patron. It works
# by calling the OpenAthens API to obtain a unique session-initiation URL
# for the patron, and then issuing a redirect to that URL. The logic
# follows the instructions for OpenAthens API-based sign-in at:
# http://docs.openathens.net/display/public/MD/Implementing+the+API+connector+in+your+code
#
# There are two flows supported:
#
# 1. The patron just logged in locally, and we want to sign them in to
#    OpenAthens as well (if this feature is enabled for the patron's home
#    library).
#
#    In this case the redirect_to parameter will have been provided in the
#    query string (by the code in sub load_openathens_sso_if_reuired), and will
#    be the local URL that initiated login, for example /eg/opac/myopac/main.
#
#    We will call the OpenAthens API via a back channel, supplying the patron's
#    unique identifier and the redirect URL. The OpenAthens API response will
#    contain a URL that can be used to establish the OpenAthens session for the
#    patron, and we redirect the patron to this URL. (The URL will contain a
#    redirect parameter instructing OpenAthens to send the patron back to the
#    originally requested local URL afterwards.
#
# 2. The patron tried to access an external website that requires an OpenAthens
#    session, and chose our Evergreen instance as their identity provider.
#    OpenAthens will therefore redirect the patron to this handler.
#
#    (This is a protected page, so if the patron is not already logged in to
#    Evergreen, EGCatLoader will request login first, and then redirect back
#    here, in the same way as any other page that requires login.)
#
#    In this case, OpenAthens will supply a returnData query string paramemter.
#    This parameter contains information about which website the patron is
#    trying to access but it is opaque to us.
#
#    We will call the OpenAthens API via a back channel, supplying the patron's
#    unique identifier and the returnData. The OpenAthens API response will
#    contain a URL that can be used to establish the OpenAthens session for the
#    patron, and we redirect the patron to this URL. The URL will contain the
#    original returnData parameter, instructing OpenAthens to send the patron
#    onward to the website they were originally trying to access, after it has
#    established their session.
#
# We do not expect to receive both redirect_to and returnData in the same
# request. This is an invalid request and results in a 400 status error. If we
# don't receive either redirect_to or returnData, that's also unexpected, but
# silently ignored by redirecting to the OPAC home. Any error calling the 
# OpenAthens API is logged for diagnostic purposes, but the patron is
# redirected to the OPAC home page rather than displaying the error. The system
# will alway try again next time they access a website that requires an
# OpenAthens session.
#
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

    # Page called with no relevant parameters; go to home.
    return $self->generic_redirect() unless ($redirect_to || $return_data);

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
    }
}

# -----------------------------------------------------------------------------
# sub load_openathens_logout
# -----------------------------------------------------------------------------
#
# Hanlder for <OPAC_ROOT>/sso/openathens/logout. Its job is to terminate the
# patron's OpenAthens session. It does this by redirecting the patron to the
# standard OpenAthens sign-out URL.
#
# The patron will only get here if their home library is configured to sign
# patrons out of OpenAthens when they log out of Evergreen. See the comment on
# sub load_openathens_signout_if_required above.
#
# The OpenAthens sign-out URL does not accept a redirect parameter. However
# the library's OpenAthens administrator can configure a fixed post-sign-out
# redirect in their OpenAthens administrator dashboard. This could be used to
# send patrons back to Evergreen after their OpenAthens session has ended.
#
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
            '+coai' => { org_unit => $org_id, active => 't' }
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
