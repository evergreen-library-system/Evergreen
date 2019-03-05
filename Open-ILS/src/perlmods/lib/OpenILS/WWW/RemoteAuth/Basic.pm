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
# - RemoteAuth handler for HTTP basic access authorization (RFC 7617)
# - patron credentials are Bas64-encoded in Authorization header
# - no client authorization - restricting access by IP or other methods
#   is strongly recommended!
# ====================================================================== 

package OpenILS::WWW::RemoteAuth::Basic;
use strict; use warnings;
use OpenILS::WWW::RemoteAuth;
use base "OpenILS::WWW::RemoteAuth";

use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN AUTH_REQUIRED HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use MIME::Base64;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenSRF::Utils::JSON;

sub new {
    my( $class, $args ) = @_;
    $args ||= {};
    $class = ref $class || $class;
    return bless($args, $class);
}

# here's our main method; it controls the various steps of the auth flow,
# prepares the response content, and returns an HTTP status code
sub process {
    my ($self, $r) = @_;
    my ($authtoken, $editor, $config);

    # authorize client
    try {
        my $client_user = $r->dir_config('OILSRemoteAuthClientUsername');
        my $client_pw = $r->dir_config('OILSRemoteAuthClientPassword');
        $authtoken = $self->do_client_auth($client_user, $client_pw);
    } catch Error with {
        $logger->error("RemoteAuth Basic failed on client auth: @_");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    };
    return $self->client_not_authorized unless $authtoken;

    # load config
    try {
        $editor = new_editor( authtoken => $authtoken );
        $config = $self->load_config($editor, $r);
    } catch Error with {
        $logger->error("RemoteAuth Basic failed on load config: @_");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    };
    return $self->backend_error unless $config;

    # extract patron id/password from Authorization request header
    my $auth_header = $r->headers_in->get('Authorization');
    unless (defined $auth_header && $auth_header =~ /^Basic /) {
        # include WWW-Authenticate header on 401 responses, per RFC 7617
        my $name = $config->name;
        $r->err_headers_out->add('WWW-Authenticate' => "Basic realm=\"$name\"");
        return Apache2::Const::AUTH_REQUIRED;
    }
    $auth_header =~ s/^Basic //;
    my ($id, $password) = split(/:/, decode_base64($auth_header), 2);

    # authenticate patron
    my $stat = $self->do_patron_auth($editor, $config, $id, $password);
    return $stat unless $stat == Apache2::Const::OK;

    # XXX RFC 7617 doesn't require any particular content in the body of the
    # response.  The response content could be made configurable, but for now,
    # let's respond with a simple JSON message containing the username/barcode
    # used to authenticate the user: it's a predictable response, it doesn't
    # require us to retrieve any additional patron information, and it's
    # compatible with the Apereo CAS server's requirements for remote REST
    # authentication, as documented here:
    # https://apereo.github.io/cas/5.0.x/installation/Rest-Authentication.html

    my $response_content = { id => $id };
    $r->content_type('application/json');
    $r->print( OpenSRF::Utils::JSON->perl2JSON($response_content) );
    return Apache2::Const::OK;

}

# ... and here are all our util methods:

# success
sub success {
    return Apache2::Const::OK;
}

# generic backend error
sub backend_error {
    return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
}

# client error (e.g. missing params)
sub client_error {
    return Apache2::Const::HTTP_BAD_REQUEST;
}

# client auth failed
sub client_not_authorized {
    return Apache2::Const::AUTH_REQUIRED;
}

# patron auth failed (bad password etc)
sub patron_not_authenticated {
    return Apache2::Const::FORBIDDEN;
}

# patron does not exist or is inactive/deleted
sub patron_not_found {
    return Apache2::Const::FORBIDDEN;
}

# patron is barred or has blocking penalties
sub patron_is_blocked {
    return Apache2::Const::FORBIDDEN;
}

# patron is expired
sub patron_is_expired {
    return Apache2::Const::FORBIDDEN;
}

1;

