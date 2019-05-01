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
# - base class for configurable HTTP API for patron auth/retrieval
# - provides generic methods shared by all handler subclasses
# - handlers take care of endpoint-specific implementation details
# ======================================================================

package OpenILS::WWW::RemoteAuth;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN AUTH_REQUIRED HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use DateTime::Format::ISO8601;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::System;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
our $U = "OpenILS::Application::AppUtils";

my $bootstrap_config;
my @handlers_to_preinit = ();

sub editor {
    my ($self, $editor) = @_;
    $self->{editor} = $editor if $editor;
    return $self->{editor};
}

sub config {
    my ($self, $config) = @_;
    $self->{config} = $config if $config;
    return $self->{config};
}

sub import {
    my ($self, $bootstrap_config, $handlers) = @_;
    @handlers_to_preinit = split /\s+/, $handlers, -1 if defined($handlers);
}

sub child_init {
    OpenSRF::System->bootstrap_client(config_file => $bootstrap_config);
    my $idl = OpenSRF::Utils::SettingsClient->new->config_value("IDL");
    Fieldmapper->import(IDL => $idl);
    OpenILS::Utils::CStoreEditor->init;
    foreach my $module (@handlers_to_preinit) {
        eval {
            $module->use;
        };
    }
    return Apache2::Const::OK;
}

sub handler {
    my $r = shift;

    my $stat = Apache2::Const::AUTH_REQUIRED;

    # load the appropriate module and process our request
    try {
        my $module = $r->dir_config('OILSRemoteAuthHandler');
        $module->use;
        my $handler = $module->new;
        $stat = $handler->process($r);
    } catch Error with {
        my $err = shift;
        $logger->error("processing RemoteAuth handler failed: $err");
        $stat = Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    };

    return $stat;
}

sub load_config {
    my ($self, $e, $r) = @_;

    # name to use for config lookup
    my $name = $r->dir_config('OILSRemoteAuthProfile');
    return undef unless $name;

    # load config
    my $config = $e->retrieve_config_remoteauth_profile($name);
    if ($config and $U->is_true($config->enabled)) {
        return $config;
    }
    $logger->info("RemoteAuth: config profile $name not found (or not enabled)");
    return undef;
}

sub do_client_auth {
    my ($self, $client_username, $client_password) = @_;
    my $login_resp = $U->simplereq(
        'open-ils.auth',
        'open-ils.auth.login', {
            username => $client_username,
            password => $client_password,
            type => 'staff'
        }   
    );
    if ($login_resp->{textcode} eq 'SUCCESS') {
        return $login_resp->{payload}->{authtoken};
    }
    $logger->info("RemoteAuth: failed to authenticate client $client_username");
    return undef;
}

sub do_patron_auth {
    my ($self, $e, $config, $id, $password) = @_;
    my $org_unit = $config->context_org;

    return $self->backend_error unless $e->checkauth;

    my $args = {
        type => 'opac', # XXX
        org => $org_unit,
        identifier => $id,
        password => $password
    };

    my $cuat = $e->retrieve_config_usr_activity_type($config->usr_activity_type);
    if ($cuat) {
        $args->{agent} = $cuat->ewho;
    }

    my $response = $U->simplereq(
        'open-ils.auth',
        'open-ils.auth.login', $args);
    if($U->event_code($response)) { 
        $logger->info("RemoteAuth: failed to authenticate user $id at org unit $org_unit");
        return $self->patron_not_authenticated;
    }

    # get basic patron info via user authtoken
    my $authtoken = $response->{payload}->{authtoken};
    my $user = $U->simplereq(
        'open-ils.auth',
        'open-ils.auth.session.retrieve', $authtoken);
    if (!$user or $U->event_code($user)) {
        $logger->error("RemoteAuth: failed to retrieve user for session $authtoken");
        return $self->backend_error;
    }
    my $userid = $user->id;
    my $home_ou = $user->home_ou;

    unless ($e->allowed('VIEW_USER', $home_ou)) {
        $logger->info("RemoteAuth: client does not have permission to view user $userid");
        return $self->client_not_authorized;
    }

    # do basic validation (and skip the permit test where applicable)
    if ($U->is_true($user->deleted)) {
        $logger->info("RemoteAuth: user $userid is deleted");
        return $self->patron_not_found;
    }

    if ($U->is_true($user->barred)) {
        $logger->info("RemoteAuth: user $userid is barred");
        return $self->patron_is_blocked;
    }

    # check if remoteauth is permitted for this user
    my $permit_test = $e->json_query(
        {from => ['actor.permit_remoteauth', $config->name, $userid]}
    )->[0]{'actor.permit_remoteauth'};;

    if ($permit_test eq 'success') {
        return $self->success($user);
    } elsif ($permit_test eq 'not_found') {
        return $self->patron_not_found;
    } elsif ($permit_test eq 'expired') {
        return $self->patron_is_expired;
    } else {
        return $self->patron_is_blocked;
    }
}

# Dummy methods for responding to the client based on
# different error (or success) conditions.
# The handler will normally want to override these methods
# with its own version of them.

# patron auth succeeded
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
    return Apache2::Const::DECLINED;
}

# patron is barred or has blocking penalties
sub patron_is_blocked {
    return Apache2::Const::FORBIDDEN;
}

# patron is expired
sub patron_is_expired {
    return Apache2::Const::DECLINED;
}

1;

