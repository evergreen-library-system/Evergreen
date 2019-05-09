#!/usr/bin/perl

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

=head1 NAME

OpenILS::Application::AuthProxy - Negotiator for proxy-style authentication

=head1 AUTHOR

Dan Wells, dbw2@calvin.edu

=cut

package OpenILS::Application::AuthProxy;

use strict;
use warnings;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Event;
use UNIVERSAL::require;
use Digest::MD5 qw/md5_hex/;
my $U = 'OpenILS::Application::AppUtils';

# NOTE: code assumes throughout that '0' is never a valid username, barcode,
# or password; some logic will need to be tweaked to support it if needed.

my @authenticators;
my %authenticators_by_name;
my $enabled = 'false';
my $cache;
my $seed_timeout;
my $block_timeout;
my $block_count;

sub initialize {
    my $conf = OpenSRF::Utils::SettingsClient->new;
    $cache = OpenSRF::Utils::Cache->new();

    my @pfx = ( "apps", "open-ils.auth", "app_settings", "auth_limits" );

    # read in (or set defaults) for brute force blocking settings
    $seed_timeout = $conf->config_value( @pfx, "seed" );
    $seed_timeout = 30 if (!$seed_timeout or $seed_timeout < 0);
    $block_timeout = $conf->config_value( @pfx, "block_time" );
    $block_timeout = $seed_timeout * 3 if (!$block_timeout or $block_timeout < 0);
    $block_count = $conf->config_value( @pfx, "block_count" );
    $block_count = 10 if (!$block_count or $block_count < 0);

    @pfx = ( "apps", "open-ils.auth_proxy", "app_settings" );

    $enabled = $conf->config_value( @pfx, 'enabled' );

    my $auth_configs = $conf->config_value( @pfx, 'authenticators', 'authenticator' );
    $auth_configs = [$auth_configs] if ref($auth_configs) eq 'HASH';

    if ( !@$auth_configs ) {
        $logger->error("AuthProxy: authenticators list not found!");
    } else {
        foreach my $auth_config (@$auth_configs) {
            my $auth_handler;
            if ($auth_config->{'name'} eq 'native') {
                $auth_handler = 'OpenILS::Application::AuthProxy::Native';
            } else {
                $auth_handler = $auth_config->{module};
                next unless $auth_handler;

                $logger->debug("Attempting to load AuthProxy handler: $auth_handler");
                $auth_handler->use;
                if($@) {
                    $logger->error("Unable to load AuthProxy handler [$auth_handler]: $@");
                    next;
                }
            }

            &_make_option_array($auth_config, 'login_types', 'type');
            &_make_option_array($auth_config, 'org_units', 'unit');

            my $authenticator = $auth_handler->new($auth_config);
            push @authenticators, $authenticator;
            $authenticators_by_name{$authenticator->name} = $authenticator;
            $logger->debug("Successfully loaded AuthProxy handler: $auth_handler");
        }
        $logger->debug("AuthProxy: authenticators loaded");
    }
}

# helper function to simplify the config structure
sub _make_option_array {
    my ($auth_config, $container_name, $node_name) = @_;

    if (exists $auth_config->{$container_name}
        and ref $auth_config->{$container_name} eq 'HASH') {
        my $nodes = $auth_config->{$container_name}{$node_name};
        if ($nodes) {
            if (ref $nodes ne 'ARRAY') {
                $auth_config->{$container_name} = [$nodes];
            } else {
                $auth_config->{$container_name} = $nodes;
            }
        } else {
            delete $auth_config->{$container_name};
        }
    } else {
        delete $auth_config->{$container_name};
    }
}



__PACKAGE__->register_method(
    method    => "enabled",
    api_name  => "open-ils.auth_proxy.enabled",
    api_level => 1,
    stream    => 1,
    argc      => 0,
    signature => {
        desc => q/Check if AuthProxy is enabled/,
        return => {
            desc => "True if enabled, false if not",
            type => "bool"
        }
    }
);
sub enabled {
    return (!$enabled or $enabled eq 'false') ? 0 : 1;
}

__PACKAGE__->register_method(
    method    => "login",
    api_name  => "open-ils.auth_proxy.login",
    api_level => 1,
    stream    => 1,
    argc      => 1,
    signature => {
        desc => q/Basic single-factor login method/,
        params => [
            {name=> "args", desc => q/A hash of arguments.  Valid keys and their meanings:
    username := Username to authenticate.
    barcode  := Barcode of user to authenticate 
    password := Password for verifying the user.
    type     := Type of login being attempted (Staff Client, OPAC, etc.).
    org      := Org unit id
/,
                type => "hash"}
        ],
        return => {
            desc => "Authentication seed or failure event",
            type => "mixed"
        }
    }
);
sub login {
    my ( $self, $conn, $args ) = @_;
    $args ||= {};

    return OpenILS::Event->new( 'LOGIN_FAILED' )
      unless (&enabled() and ($args->{'username'} or $args->{'barcode'}));

    # provided username may not be the user's actual EG username;
    # hang onto the provided value (if any) so we can use it later
    $args->{'provided_username'} = $args->{'username'};

    if ($args->{barcode} and !$args->{username}) {
        # translate barcode logins into username logins by locating
        # the matching card/user and collecting the username.

        my $card = new_editor()->search_actor_card([
            {barcode => $args->{barcode}, active => 't'},
            {flesh => 1, flesh_fields => {ac => ['usr']}}
        ])->[0];

        if ($card) {
            $args->{username} = $card->usr->usrname;
        } else { # must have or resolve to a username
            return OpenILS::Event->new( 'LOGIN_FAILED' );
        }
    }

    # check for possibility of brute-force attack
    my $fail_count = $cache->get_cache('oils_auth_' . $args->{'username'} . '_count') || 0;
    if ($fail_count >= $block_count) {
        $logger->debug("AuthProxy found too many recent failures for '" . $args->{'username'} . "' : $fail_count, forcing failure state.");
        $cache->put_cache('oils_auth_' . $args->{'username'} . '_count', ++$fail_count, $block_timeout);
        return OpenILS::Event->new( 'LOGIN_FAILED' );
    }

    my @error_events;
    my $authenticated = 0;
    my $auths;

    # if they specify an authenticator by name, only try that one
    if ($args->{'name'}) {
        $auths = [$authenticators_by_name{$args->{'name'}}];
    } else {
        $auths = \@authenticators;
    }

    foreach my $authenticator (@$auths) {
        # skip authenticators specified for a different login type
        # or org unit id
        if ($authenticator->login_types and $args->{'type'}) {
            next unless grep(/^(all|$args->{'type'})$/, @{$authenticator->{'login_types'}});
        }
        if ($authenticator->org_units and $args->{'org'}) {
            next unless grep(/^(all|$args->{'org'})$/, @{$authenticator->{'org_units'}});
        }

        my $event;
        # treat native specially
        if ($authenticator->name eq 'native') {
            $event = &_do_login($args);
        } else {
            $event = $authenticator->authenticate($args);
        }
        my $code = $U->event_code($event);
        if ($code) {
            push @error_events, $event;
        } elsif (defined $code) { # code is '0', i.e. SUCCESS
            if ($authenticator->name eq 'native' and exists $event->{'payload'}) { # we have a complete native login
                return $event;
            } else { # create an EG session for the successful external login
                # if external login returns a payload, that payload is the
                # user's Evergreen username
                if ($event->{'payload'}) {
                    $args->{'username'} = $event->{'payload'};
                }

                # before we actually create the session, let's first check if
                # Evergreen thinks this user is allowed to login
                #
                # (we do this *after* authentication to avoid any personal data
                # leakage)

                # get the user id
                my $user = $U->cstorereq(
                    "open-ils.cstore.direct.actor.user.search.atomic",
                    { usrname => $args->{'username'} }
                );
                if (!$user->[0]) {
                    $logger->debug("Authenticated username '" . $args->{'username'} . "' has no Evergreen account, aborting");
                    return OpenILS::Event->new( 'LOGIN_FAILED' );
                } else {
                    my $restrict_by_ou = $authenticator->{restrict_by_home_ou};
                    if (defined($restrict_by_ou) and $restrict_by_ou =~ /^t/i) {
                        my $home_ou = $user->[0]->home_ou;
                        my $allowed = 0;
                        # disallow auth if user's home library is not one of the org_units for this authenticator
                        if ($authenticator->org_units) {
                            if (grep(/^all$/, @{$authenticator->org_units})) {
                                $allowed = 1;
                            } else {
                                foreach my $org (@{$authenticator->org_units}) {
                                    my $allowed_orgs = $U->get_org_descendants($org);
                                    if (grep(/^$home_ou$/, @$allowed_orgs)) {
                                        $allowed = 1;
                                        last;
                                    }
                                }
                            }
                            if (!$allowed) {
                                $logger->debug("Auth disallowed for matching user's home library, aborting");
                                return OpenILS::Event->new( 'LOGIN_FAILED' );
                            }
                        }
                    }
                    $args->{user_id} = $user->[0]->id;
                }

                # validate the account
                my $trimmed_args = {
                    user_id => $args->{user_id},
                    login_type => $args->{type},
                    workstation => $args->{workstation},
                    org_unit => $args->{org}
                };
                $event = &_auth_internal('user.validate', $trimmed_args);
                if ($U->event_code($event)) { # non-zero = we didn't succeed
                    # can't recover from invalid user, return right away
                    return $event;
                } else { # it's all good
                    return &_auth_internal('session.create', $trimmed_args);
                }
            }
        }
    }

    # if we got this far, we failed
    # increment the brute force counter if 'native' didn't already
    if (!exists $authenticators_by_name{'native'}) {
        $cache->put_cache('oils_auth_' . $args->{'username'} . '_count', ++$fail_count, $block_timeout);
    }
    # TODO: send back some form of collected error events
    return OpenILS::Event->new( 'LOGIN_FAILED' );
}

sub _auth_internal {
    my ($method, $args) = @_;

    my $response = OpenSRF::AppSession->create("open-ils.auth_internal")->request(
        'open-ils.auth_internal.'.$method,
        $args
    )->gather(1);

    return OpenILS::Event->new( 'LOGIN_FAILED' )
      unless $response;

    return $response;
}

sub _do_login {
    my $args = shift;
    my $response = OpenSRF::AppSession->create("open-ils.auth")->request(
        'open-ils.auth.login',
        $args
    )->gather(1);

    return OpenILS::Event->new( 'LOGIN_FAILED' )
      unless $response;

    return $response;
}

__PACKAGE__->register_method(
    method    => "authenticators",
    api_name  => "open-ils.auth_proxy.authenticators",
    api_level => 1,
    stream    => 1,
    argc      => 1,
    signature => {
        desc => q/Get a list of viable authenticators/,
        params => [
            {name=> "args", desc => q/A hash of arguments.  Valid keys and their meanings:
    type     := Type of login being attempted (Staff Client, OPAC, etc.).
    org      := Org unit id
/,
                type => "hash"}
        ],
        return => {
            desc => "List of viable authenticators",
            type => "array"
        }
    }
);
sub authenticators {
    my ( $self, $conn, $args ) = @_;

    my @viable_auths;

    foreach my $authenticator (@authenticators) {
        # skip authenticators specified for a different login type
        # or org unit id
        if ($authenticator->login_types and $args->{'type'}) {
            next unless grep(/^(all|$args->{'type'})$/, @{$authenticator->login_types});
        }
        if ($authenticator->org_units and $args->{'org'}) {
            next unless grep(/^(all|$args->{'org'})$/, @{$authenticator->org_units});
        }

        push @viable_auths, $authenticator->name;
    }

    return \@viable_auths;
}


# --------------------------------------------------------------------------
# Stub package for 'native' authenticator
# --------------------------------------------------------------------------
package OpenILS::Application::AuthProxy::Native;
use strict; use warnings;
use base 'OpenILS::Application::AuthProxy::AuthBase';

1;
