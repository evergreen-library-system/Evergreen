# Copyright (C) 2019 BC Libraries Cooperative
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# ====================================================================== 
# - RemoteAuth handler for EZProxy CGI authentication:
#   https://help.oclc.org/Library_Management/EZproxy/Authenticate_users/EZproxy_authentication_methods/CGI_authentication
# ====================================================================== 

package OpenILS::WWW::RemoteAuth::EZProxyCGI;
use strict; use warnings;
use OpenILS::WWW::RemoteAuth;
use base "OpenILS::WWW::RemoteAuth";

use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN AUTH_REQUIRED HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use CGI qw(:all -utf8);
use URI::Escape;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenSRF::Utils::JSON;
use OpenILS::WWW::RemoteAuth::Template;

sub new {
    my( $class, $args ) = @_;
    $args ||= {};
    $args->{cgi} ||= new CGI;
    $class = ref $class || $class;
    return bless($args, $class);
}

sub r {
    my ($self, $r) = @_;
    $self->{r} = $r if $r;
    return $self->{r};
}

# CGI handle
sub cgi {
    my($self, $cgi) = @_; 
    $self->{cgi} = $cgi if $cgi;
    return $self->{cgi};
}

sub process {
    my ($self, $r) = @_;
    my ($authtoken, $editor, $config);

    $self->r($r);

    # get params from incoming request
    $self->{args} = {
        id => scalar $self->cgi->param('id'),
        password => scalar $self->cgi->param('password'),
        url => scalar $self->cgi->param('url')
    };

    return $self->login unless (defined $self->{args}->{id} and defined $self->{args}->{password});

    # authorize client
    try {
        my $client_user = $r->dir_config('OILSRemoteAuthClientUsername');
        my $client_pw = $r->dir_config('OILSRemoteAuthClientPassword');
        $authtoken = $self->do_client_auth($client_user, $client_pw);
    } catch Error with {
        $logger->error("RemoteAuth EZProxyCGI failed on client auth: @_");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    };
    return $self->client_not_authorized unless $authtoken;

    # load config
    try {
        $editor = new_editor( authtoken => $authtoken );
        $config = $self->load_config($editor, $r);
    } catch Error with {
        $logger->error("RemoteAuth EZProxyCGI failed on load config: @_");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    };
    return $self->backend_error unless $config;

    # authenticate patron
    # this uses our util methods (success, patron_not_found, etc) to return the
    # appropriate response depending on the outcome of the auth request:
    # - if auth succeeded, redirect to EZProxy
    # - otherwise, TT2-based error page or login form
    return $self->do_patron_auth($editor, $config, $self->{args}->{id}, $self->{args}->{password});
}

sub ezproxy_url {
    my ($r, $url, $user, $groups) = @_;
    my ($packet, $ticket);

    my $secret = $r->dir_config('OILSRemoteAuthEZProxySecret');
    my $base_uri = $r->dir_config('OILSRemoteAuthEZProxyBaseURI');

	return unless defined($secret);

    # generate ticket
    $packet = '$u' . time();
    if ($groups) {
        $packet .= '$g' . $groups;
    }
    $packet .= '$e';
    $ticket = md5_hex($secret . $user . $packet) . $packet;

    # escape our URL params
    $user = uri_escape($user);
    $ticket = uri_escape($ticket);
    $url = uri_escape($url);

    return "$base_uri/login?user=$user&ticket=$ticket&url=$url";
}

# redirect to EZProxy URL on successful auth
sub success {
    my ($self, $user) = @_;
    my $redirect_url = ezproxy_url($self->r, $self->{args}->{url}, $user->usrname);
    print $self->cgi->redirect($redirect_url);
    return Apache2::Const::REDIRECT;
}

# show login form
sub login {
    my $self = shift;
    my $ctx = {
        page => 'login',
        args => $self->{args}
    };
    my $tt = new OpenILS::WWW::RemoteAuth::Template;
    return $tt->process('login', $ctx, $self->r);
}

# wrapper method for auth failures
sub error {
    my ($self, $msg) = @_;
    my $ctx = {
        page => 'error',
        args => $self->{args},
        error_msg => $msg
    };
    my $tt = new OpenILS::WWW::RemoteAuth::Template;
    return $tt->process('error', $ctx, $self->r);
}

# generic backend error
sub backend_error {
    my $self = shift;
    return $self->error('backend_error');
}

# client error (e.g. missing params)
sub client_error {
    my $self = shift;
    return $self->error('client_error');
}

# client auth failed
sub client_not_authorized {
    my $self = shift;
    return $self->error('client_not_authorized');
}

# patron auth failed (bad password etc)
sub patron_not_authenticated {
    my $self = shift;
    return $self->error('patron_not_authenticated');
}

# patron does not exist or is inactive/deleted
sub patron_not_found {
    my $self = shift;
    return $self->error('patron_not_found');
}

# patron is barred or has blocking penalties
sub patron_is_blocked {
    my $self = shift;
    return $self->error('patron_is_blocked');
}

# patron is expired
sub patron_is_expired {
    my $self = shift;
    return $self->error('patron_is_expired');
}

1;

