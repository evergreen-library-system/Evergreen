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
# - RemoteAuth handler for PatronAPI authentication:
#   https://csdirect.iii.com/sierrahelp/Content/sril/sril_patronapi.html
# ======================================================================

package OpenILS::WWW::RemoteAuth::PatronAPI;
use strict; use warnings;
use OpenILS::WWW::RemoteAuth;
use base "OpenILS::WWW::RemoteAuth";

use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN AUTH_REQUIRED HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use File::Spec;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenSRF::Utils::JSON;
use OpenILS::WWW::RemoteAuth::Template;

sub new {
    my( $class, $args ) = @_;
    $args ||= {};
    $args->{request_type} ||= 'default';
    $class = ref $class || $class;
    return bless($args, $class);
}

sub r {
    my ($self, $r) = @_;
    $self->{r} = $r if $r;
    return $self->{r};
}

sub request_type {
    my ($self, $request_type) = @_;
    $self->{request_type} = $request_type if $request_type;
    return $self->{request_type};
}

sub process {
    my ($self, $r) = @_;
    my ($authtoken, $editor, $config);

    $self->r($r);

    # authorize client
    try {
        my $client_user = $r->dir_config('OILSRemoteAuthClientUsername');
        my $client_pw = $r->dir_config('OILSRemoteAuthClientPassword');
        $authtoken = $self->do_client_auth($client_user, $client_pw);
    } catch Error with {
        $logger->error("RemoteAuth PatronAPI failed on client auth: @_");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    };
    return $self->client_not_authorized unless $authtoken;

    # load config
    try {
        $editor = new_editor( authtoken => $authtoken );
        $config = $self->load_config($editor, $r);
    } catch Error with {
        $logger->error("RemoteAuth PatronAPI failed on load config: @_");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    };
    return $self->backend_error unless $config;

    my $allow_dump = $r->dir_config('OILSRemoteAuthPatronAPIAllowDump') || 'false';
    my $id_type = $r->dir_config('OILSRemoteAuthPatronAPIIDType') || 'barcode';

    # parse request
    my $path = $r->path_info;
    $path =~ s|/*\$||; # strip any trailing slashes
    my @params = reverse File::Spec->splitdir($path);
    $self->request_type(shift @params);

    if ($self->request_type eq 'dump') {
        unless ($allow_dump eq 'true') {
            return $self->client_not_authorized;
        }
        my ($id, @leftovers) = @params;
        return $self->get_patron_info($editor, $config, { $id_type => $id });

    } elsif ($self->request_type eq 'pintest') {
        my ($password, $id, @leftovers) = @params;
        return $self->do_patron_auth($editor, $config, $id, $password);

    } else {
        $logger->error("RemoteAuth PatronAPI: invalid request format");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }
}

sub success {
    my ($self, $user) = @_;
    my $template = $self->request_type;
    my $ctx = {
        result => 'success',
        user => $user
    };
    my $tt = new OpenILS::WWW::RemoteAuth::Template;
    return $tt->process($template, $ctx, $self->r);
}

# wrapper method for auth failures
sub error {
    my ($self, $msg) = @_;
    my $template = $self->request_type;
    my $ctx = {
        result => 'error',
        error_msg => $msg
    };
    my $tt = new OpenILS::WWW::RemoteAuth::Template;
    return $tt->process($template, $ctx, $self->r);
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


