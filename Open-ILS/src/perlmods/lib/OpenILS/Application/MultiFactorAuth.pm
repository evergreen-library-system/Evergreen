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

OpenILS::Application::MultiFactorAuth - Facilitates triggering MFA and
using MFA to upgrade provisional sessions to full sessions

=head1 AUTHOR

Mike Rylander <mrylander@gmail.com>

=cut

package OpenILS::Application::MultiFactorAuth;

use strict;
use warnings;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenSRF::AppSession;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Event;
use List::MoreUtils qw(uniq);
use Encode;
use Pass::OTP;
use Pass::OTP::URI;
use Authen::WebAuthn;
use Email::Valid;
use MIME::Base64;
my $U = 'OpenILS::Application::AppUtils';

my %factors;
my %factor_flags;
my %factor_validators;
my $factor_configs;

our $cache;
our $enabled = 'false';
our $secondary = 'false';

sub initialize {
    my $conf = OpenSRF::Utils::SettingsClient->new;

    my $settings = $conf->config_value( qw/apps open-ils.auth_mfa app_settings/ );
    $enabled = $$settings{enabled};
    $secondary = $$settings{honor_secondary_groups};
    $logger->info("MFA enable: $enabled");
    $logger->info("MFA honors secondary group membership: $secondary");

    $factor_configs = $$settings{factors};
    $factor_configs = {} if ref($factor_configs) ne 'HASH';

    $logger->info("MFA factors with configuration file information: ".join(' ', keys(%$factor_configs)));

    return 1;
}

sub child_init {
    $cache = OpenSRF::Utils::Cache->new('global');
}

sub _init {
    return if keys %factors;

    my $e = new_editor();
    %factors = map { ($_->name => {object => $_}) } @{$e->retrieve_all_config_mfa_factor};
    $logger->info("MFA factors with database information: ".join(' ', keys(%factors)));
    
    for my $factor (keys %$factor_configs) {
        $logger->info("Initializing MFA factor from config file: $factor");
        
        unless (exists $factors{$factor}) {
            # we have to know about it in advance. maybe plugins later.
            $logger->info("Unknown MFA factor in config file: $factor");
            next;
        }

        $factors{$factor} = { # copy it over
            %{$factors{$factor}},
            %{$$factor_configs{$factor}}
        };

        # then normalize some parts
        $factors{$factor}{enabled} = lc($factors{$factor}{enabled} || 'false') eq 'true' ? 1 : 0;
        $logger->info("MFA factor enabled: $factor") if $factors{$factor}{enabled};

        # stub validator -- fail-by-default
        $factor_validators{$factor}{mfa} //= sub { return 0 };
        $factor_validators{$factor}{login} //= sub { return 0 };

        # every factor gets a fuzziness setting that we default to 1
        $factors{$factor}{mfa}{fuzziness} //= $factors{$factor}{fuzziness} // 1;
        $factors{$factor}{login}{fuzziness} //= $factors{$factor}{fuzziness} // 1;

        for my $flag_type (qw/period digits algorithm issuer domain multicred/) {
            my $flags = $e->search_config_global_flag({
                name => ["$factor.mfa.$flag_type", "$factor.login.$flag_type"],
                enabled => 1
            });

            if (@$flags) {
                ($factor_flags{$factor}{mfa}{$flag_type}) = grep {$_->name eq "$factor.mfa.$flag_type"} @$flags;
                ($factor_flags{$factor}{login}{$flag_type}) = grep {$_->name eq "$factor.login.$flag_type"} @$flags;
            }
        }
    }
}

sub get_factor_flag {
    my $factor = shift;
    my $purpose = shift;
    my $flag = shift;

    return $factor_flags{$factor}{$purpose}{$flag};
}

__PACKAGE__->register_method(
    method    => "factor_details",
    api_name  => "open-ils.auth_mfa.factor_details",
    api_level => 1,
    argc      => 0,
    signature => {
        desc => q/Supply IDL object describing factors enabled for use/,
        return => {
            desc => "Hash of IDL objects, keyed by factor name",
            type => "object"
        }
    }
);
sub factor_details {
    my $self = shift;
    my $client = shift;
    my $factors = shift;

    _init();
    return {} unless $enabled eq 'true'; # check the master switch
    my $enabled_factors = enabled_factor_list();
    return {} unless (@$enabled_factors); # no factors?

    $factors = [$factors] unless (ref($factors) and ref($factors) eq 'ARRAY');

    my %result;
    my %flags;
    for my $f (@$factors) {
        return {} unless ($f and !ref($f));
        next unless (grep {$_ eq $f} @$enabled_factors);
        $result{$f} = $factors{$f}{object};
        for my $flag_type (qw/period digits algorithm issuer domain multicred/) {
            my $flag_value = get_factor_flag($f => mfa => $flag_type);
            if (defined $flag_value) {
                $flags{$f}{$flag_type} = $flag_value;
            }
        }
    }

    return { factors => \%result, flags => \%flags };
}

__PACKAGE__->register_method(
    method    => "enabled",
    api_name  => "open-ils.auth_mfa.enabled",
    api_level => 1,
    argc      => 0,
    signature => {
        desc => q/Check if MFA is enabled/,
        return => {
            desc => "True if enabled, false if not",
            type => "bool"
        }
    }
);
sub enabled {
    _init();
    return 0 unless $enabled eq 'true'; # check the master switch
    return 0 unless scalar(@{enabled_factor_list()}); # no factors? disabled
    return 1;
}

sub secondary {
    return 0 unless $secondary eq 'true';
    return 1;
}

__PACKAGE__->register_method(
    method    => "enabled_factor_list",
    api_name  => "open-ils.auth_mfa.enabled_factors",
    api_level => 1,
    argc      => 0,
    signature => {
        desc => q/Return the list of globally available MFA factors/,
        return => {
            desc => "List of configured factors",
            type => "array"
        }
    }
);
sub enabled_factor_list {
    _init();
    return [grep { $factors{$_}{enabled} } keys %factors];
}

__PACKAGE__->register_method(
    method    => "factors_for_token",
    api_name  => "open-ils.auth_mfa.token_factors.available.provisional",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/List MFA factors available for a provisional token/,
        return => {
            desc => "List of factors configured and available to the user associated ".
                    "with a provisional token; undef if none are configured and available, ".
                    "or not allowed",
            type => "array"
        }
    }
);
__PACKAGE__->register_method(
    method    => "factors_for_token",
    api_name  => "open-ils.auth_mfa.token_factors.configured.provisional",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/List MFA factors configured for a provisional token's user/,
        return => {
            desc => "List of factors configured and available to the user associated ".
                    "with a provisional token; undef if none are configured and available, ".
                    "or not allowed; empty if some are available but not configured",
            type => "array"
        }
    }
);
__PACKAGE__->register_method(
    method    => "factors_for_token",
    api_name  => "open-ils.auth_mfa.token_factors.configured.detail.provisional",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/Provides a hash of configured factors, activity, and other relevant data for a provisional token's user/,
        return => {
            desc => "Hash of activity and factors configured and available to the user associated ".
                    "with a provisional token; undef if none are configured and available, ".
                    "or not allowed; empty if some are available but not configured",
            type => "object"
        }
    }
);
__PACKAGE__->register_method(
    method    => "factors_for_token",
    api_name  => "open-ils.auth_mfa.token_factors.available",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/List MFA factors available for a real token/,
        return => {
            desc => "List of factors configured and available to the user associated ".
                    "with a token; undef if none are configured and available, ".
                    "or not allowed",
            type => "array"
        }
    }
);
__PACKAGE__->register_method(
    method    => "factors_for_token",
    api_name  => "open-ils.auth_mfa.token_factors.configured",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/List MFA factors configured for a real token's user/,
        return => {
            desc => "List of factors configured and available to the user associated ".
                    "with a token; undef if none are configured and available, ".
                    "or not allowed; empty if some are available but not configured",
            type => "array"
        }
    }
);
__PACKAGE__->register_method(
    method    => "factors_for_token",
    api_name  => "open-ils.auth_mfa.token_factors.configured.detail",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/Provides a hash of configured factors, activity, and other relevant data for a real token's user/,
        return => {
            desc => "Hash of activity and factors configured and available to the user associated ".
                    "with a token; undef if none are configured and available, ".
                    "or not allowed; empty if some are available but not configured",
            type => "object"
        }
    }
);
sub factors_for_token {
    _init();
    my $self = shift;
    my $client = shift;
    my $token = shift;
    my $e = new_editor(xact => 1);

    return undef unless (enabled() and $token); # no token, or not enabled, no MFA
    $logger->warn("Checking MFA factors for token: ". $token);

    my $usr;
    if ($self->api_name =~ /provisional$/) {
        my ($allowed) = $self->method_lookup('open-ils.auth_mfa.allowed_for_token.provisional')->run($token);
        $logger->info("MFA allowed? ". $allowed);
        return undef unless $allowed;

        my $provisional_session = $U->check_provisional_session($token);
        $usr = $$provisional_session{userobj};
    } else {
        my ($allowed) = $self->method_lookup('open-ils.auth_mfa.allowed_for_token')->run($token);
        $logger->info("MFA allowed? ". $allowed);
        return undef unless $allowed;

        $usr = $U->check_user_session($token);
    }

    $logger->warn("MFA user not found for token: ". $token) unless $usr;
    return undef unless $usr; # no session, no MFA

    $logger->info("MFA user id: ". $usr->id);
    my $grp_id_list = [$usr->profile];
    if (secondary()) {
        push @$grp_id_list, map {$_->grp} @{$e->search_permission_usr_grp_map({usr => $usr->id})};
    }

    # check group factor list against enabled factors, return 0 if no overlap
    my $grp_ancestors = [ uniq map { @$_ } map { $U->get_grp_ancestors($_) } @$grp_id_list ];
    $logger->info("MFA user groups: ". join(' ', @$grp_ancestors));

    my $group_factors = $e->search_permission_group_mfa_factor_map({
        grp => $grp_ancestors,
        factor => enabled_factor_list()
    });
    my @uniq_grp_factors = uniq map { $_->factor } @$group_factors;
    $logger->info("MFA group factors: ". join(' ', @uniq_grp_factors));
    return rollback_and_undef($e) unless scalar(@uniq_grp_factors);

    my @factors_to_offer;

    # in "available" mode, return the full available list
    if ($self->api_name =~ /available/) {
        push @factors_to_offer, @uniq_grp_factors;
    } else {
        # in "configured" mode, return the available list filtered to those the user has configured
        my $allowed_configured_factors = $e->search_actor_usr_mfa_factor_map([
            {usr => $usr->id, factor => \@uniq_grp_factors},
            {order_by => [{class => aumfm => field => 'add_time'}]}
        ]);

        if ($self->api_name =~ /detail/) { # hash w/ activity instead of just factor names, only available for real tokens
            my $type_ids = $e->search_config_usr_activity_type([{ewhat => 'confirm', egroup => 'mfa'}],{idlist => 1});
            my $usr_activity = $e->search_actor_usr_activity([
                {usr => $usr->id, etype => $type_ids},
                {order_by => [{class => auact => field => event_time => direction => 'desc'}], limit => 1}
            ]);

            my $response = {
                factors  => $allowed_configured_factors,
                activity => $$usr_activity[0]
            };

            if (grep { $_ eq 'webauthn'} @uniq_grp_factors) {
                my $otp_uri = $e->json_query({ from => [ 'actor.otpauth_uri' => $usr->id, 'webauthn' ] })->[0];
                if ($otp_uri and $$otp_uri{'actor.otpauth_uri'}) {
                    my $otp_parts = unescape_otp_hash(Pass::OTP::URI::parse($$otp_uri{'actor.otpauth_uri'}));
                    if (my $RPs = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{RPs})) {
                        $$response{webauthn}{RPs} = $RPs;
                    }
                }
            }

            $e->rollback;
            return $response;
        }

        push @factors_to_offer, map { $_->factor } @$allowed_configured_factors;
    }

    $e->rollback;
    return \@factors_to_offer;
}

sub user_has_exceptions {
    return scalar(@{get_user_exceptions(@_)});
}

sub get_user_exceptions {
    return new_editor()->search_actor_usr_mfa_exception({
        usr => $_[0],
        '-or' => [
            { ingress => undef }, # NULL means all
            { ingress => OpenSRF::AppSession->ingress }
        ]
    });
}

__PACKAGE__->register_method(
    method    => "proceed_for_token",
    api_name  => "open-ils.auth_mfa.required_for_token.provisional",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/Check if MFA is required for this provisional token to be upgraded/,
        return => {
            desc => "True if required for token upgrade, false if not",
            type => "bool"
        }
    }
);
__PACKAGE__->register_method(
    method    => "proceed_for_token",
    api_name  => "open-ils.auth_mfa.allowed_for_token.provisional",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/Check if prompting for MFA is allowed for this provisional token/,
        return => {
            desc => "True if allowed generally (enabled, group configured, enough data, no user excpetions), false otherwise",
            type => "bool"
        }
    }
);
__PACKAGE__->register_method(
    method    => "proceed_for_token",
    api_name  => "open-ils.auth_mfa.required_for_token",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/Check if MFA is required for this user to log in again/,
        return => {
            desc => "True if required for login, false if not",
            type => "bool"
        }
    }
);
__PACKAGE__->register_method(
    method    => "proceed_for_token",
    api_name  => "open-ils.auth_mfa.allowed_for_token",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/Check if prompting for MFA is allowed for this logged in user/,
        return => {
            desc => "True if allowed generally (enabled, group configured, enough data, no user excpetions), false otherwise",
            type => "bool"
        }
    }
);
sub proceed_for_token {
    _init();
    my $self = shift;
    my $client = shift;
    my $token = shift;
    my $e = new_editor();

    return 0 unless (enabled() and $token); # no token, or not enabled, no MFA

    my $usr;
    if ($self->api_name =~ /provisional$/) {
        my $provisional_session = $U->check_provisional_session($token);
        $usr = $$provisional_session{userobj};
    } else {
        $usr = $U->check_user_session($token);
    }

    return 0 unless $usr; # no session, no MFA

    # If MFA is not allowed for the group, say so
    my $grp_id_list = [$usr->profile];
    if (secondary()) {
        push @$grp_id_list, map {$_->grp} @{$e->search_permission_usr_grp_map({usr => $usr->id})};
    }

    my $grps = $e->search_permission_grp_tree({id => $grp_id_list});
    return 0 unless grep { $U->is_true($_->mfa_allowed) } @$grps;

    # check exception list, return 0 if excepted
    return 0 if user_has_exceptions($usr->id);

    # The difference between "required" and "allowed" modes is the recent-activity check,
    # which only matters to "required" mode. If they have recent MFA activity recorded, it
    # is not required.
    if ( $self->api_name =~ /required/ and grep { $U->is_true($_->mfa_required) } @$grps) {
        # check recent mfa user activity, return 0 if activity age < interval
        # IOW, it's not required /right this moment/.

        my $required_interval = $U->ou_ancestor_setting_value($usr->ws_ou, 'auth.mfa_expire_interval') || '0 seconds';
        $required_interval = "-$required_interval" unless ($required_interval =~ /^-/);

        my $type_ids = $e->search_config_usr_activity_type([{ewhat => 'confirm', egroup => 'mfa'}],{idlist => 1});
        my $usr_activity = $e->search_actor_usr_activity({
            usr => $usr->id,
            etype => $type_ids,
            event_time => {
                between => {
                    transform => 'age',
                    params    => ['now'],
                    value     => [$required_interval,'0 seconds']
                } # age of event time < interval, and not in the future
            }
        });

        return 0 if ($usr_activity and scalar(@$usr_activity));
    }

    return scalar(grep { $U->is_true($_->mfa_required) } @$grps) if ($self->api_name =~ /required/);

    # no activity, so MFA is both allowed and required
    return 1;
}

__PACKAGE__->register_method(
    method    => "sms_carriers",
    api_name  => "open-ils.auth_mfa.sms_carriers",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/Return SMS carrier objects, if relevant and allowed/,
        return => {
            desc => "List of SMS carriers, or undef if not relevant/allowed",
            type => "array"
        }
    }
);
__PACKAGE__->register_method(
    method    => "sms_carriers",
    api_name  => "open-ils.auth_mfa.sms_carriers.provisional",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/Return SMS carrier objects, if relevant and allowed/,
        return => {
            desc => "List of SMS carriers, or undef if not relevant/allowed",
            type => "array"
        }
    }
);
sub sms_carriers {
    _init();
    my $self = shift;
    my $client = shift;
    my $token = shift;

    # pre-flight checks
    return undef unless (enabled() and $token); # no token, or not enabled, no MFA

    my ($usr, $token_factors);
    if ($self->api_name =~ /provisional$/) {
        my ($allowed) = $self->method_lookup('open-ils.auth_mfa.allowed_for_token.provisional')->run($token);
        return undef unless $allowed;

        ($token_factors) = $self->method_lookup('open-ils.auth_mfa.token_factors.available.provisional')->run($token);
        my $provisional_session = $U->check_provisional_session($token);
        $usr = $$provisional_session{userobj};
    } else {
        my ($allowed) = $self->method_lookup('open-ils.auth_mfa.allowed_for_token')->run($token);
        return undef unless $allowed;

        ($token_factors) = $self->method_lookup('open-ils.auth_mfa.token_factors.available')->run($token);
        $usr = $U->check_user_session($token);
    }

    return undef unless ref $token_factors; # returns undef for "not even allowed"
    return undef unless $usr; # no session, no MFA
    return undef unless grep {/sms/} @$token_factors ; # no session, no MFA

    return new_editor()->search_config_sms_carrier([
        {active => 't'},
        {order_by => [{class => csc => field => 'name'}]}
    ]);
}

__PACKAGE__->register_method(
    method    => "mfa_ptoken_init",
    api_name  => "open-ils.auth_mfa.process.init",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/MFA initialization hook, if required by a factor/,
        return => {
            desc => "True if successful, false for any error",
            type => "bool"
        }
    }
);
sub mfa_ptoken_init {
    _init();
    my $self = shift;
    my $client = shift;
    my $token = shift;
    my $factor = shift;

    # pre-flight checks
    return 0 unless (enabled() and $token); # no token, or not enabled, no MFA
    my ($token_factors) = $self->method_lookup('open-ils.auth_mfa.token_factors.configured.provisional')->run($token);
    return 0 unless defined $token_factors; # returns undef for "not even allowed"
    return 0 unless (grep { $factor eq $_ } @$token_factors); # unconfigured or unknown factor}

    # nothing to do for these
    return 1 if grep { $factor eq $_ } qw/hotp totp static/;

    # other factors need bits from the otpauth config
    my $provisional_session = $U->check_provisional_session($token);
    return 0 unless $provisional_session;

    my $usr = $provisional_session->{userobj};
    return 0 unless $usr;

    if ($factor eq 'webauthn') {
        if (my $init_data = build_webauthn_challenge($usr, @_)) {
            $logger->info("MFA $factor: init -> stashing init_data");
            $cache->put_cache(
                "mfa.$factor.$token.validate_init_cache",
                $init_data,
                get_factor_flag($factor => mfa => 'period')->value * 2
            );
            return 1;
        }
        return 0;
    }

    return send_otp_factor_challenge($usr, $factor) ? 1 : 0;
}

__PACKAGE__->register_method(
    method    => "mfa_removal_init",
    api_name  => "open-ils.auth_mfa.removal.init",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/MFA removal initialization hook, if required by a factor/,
        return => {
            desc => "True if successful, false for any error",
            type => "bool"
        }
    }
);
sub mfa_removal_init {
    _init();
    my $self = shift;
    my $client = shift;
    my $token = shift;
    my $factor = shift;

    # pre-flight checks
    return 0 unless (enabled() and $token); # no token, or not enabled, no MFA
    my ($token_factors) = $self->method_lookup('open-ils.auth_mfa.token_factors.configured')->run($token);
    return 0 unless defined $token_factors; # returns undef for "not even allowed"
    return 0 unless (grep { $factor eq $_ } @$token_factors); # unconfigured or unknown factor}

    # nothing to do for these
    return 1 if grep { $factor eq $_ } qw/hotp totp static/;

    my $usr = $U->check_user_session($token);
    return 0 unless $usr;

    if ($factor eq 'webauthn') {
        if (my $init_data = build_webauthn_challenge($usr, @_)) {
            $logger->info("MFA $factor: removal init -> stashing init_data");
            $cache->put_cache(
                "mfa.$factor.$token.validate_init_cache",
                $init_data,
                get_factor_flag($factor => mfa => 'period')->value * 2
            );
            return 1;
        }
        return 0;
    }

    return send_otp_factor_challenge($usr, $factor) ? 1 : 0;
}

# We use this instead of a decode/encode cycle of MIME::Base64 methods
# for two reasons:
#  1) it's (probably) faster, esp. main->url
#  2) we can be sure no encoding or charset issues creep in
sub to_base64_type {
    $_ = shift;
    my $type = shift || 'not-url';

    if ($type eq 'url') {         # !!! base64url variant
        tr#/+=#_-#d;              #   use URI-safe chars
    } else {                      # !!! main standard
        tr#_-#/+#;                #   use / and + in strings
        my $len = length($_) % 4; #   pad with = to 4-char multiple
        $_ .= '='x(4 - $len) if $len;
    }

    return $_;
}

sub build_webauthn_challenge {
    my $usr = shift;
    my $hostname = shift;
    my $factor = shift || 'webauthn';
    my $purpose = shift || 'mfa';

    return undef unless ($hostname);

    my $e = new_editor();
    my $otp_uri = $e->json_query({ from => [ 'actor.otpauth_uri' => $usr->id, $factor, $purpose ] })->[0];

    if ($otp_uri and $$otp_uri{'actor.otpauth_uri'}) {
        my $otp_parts = unescape_otp_hash(Pass::OTP::URI::parse($$otp_uri{'actor.otpauth_uri'}));


        if (my $configured_RP = get_factor_flag($factor => $purpose => 'domain')->value) {
            # Setting webauthn.$purpose.domain to the base domain allows one credential
            # to cover all hostname-deliniated login locations as in a consortial setup
            $hostname = $configured_RP if ($hostname =~ /$configured_RP$/i);
        }
        return undef unless ($hostname);

        my $init_data = {};

        if (my $RPs = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{RPs})) {
            if (my ($known_RP) = grep { $_ eq $hostname } @$RPs) {
                my $known_creds = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{$known_RP});

                return undef unless (@$known_creds); # d'oh! no creds for this RP

                $$init_data{allowCredentials_b64} = [];
                for my $credId (@$known_creds) { # looping through these makes sure we actually have the credential data, not just the id
                    if (my $exCred = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{$credId})) {
                        push @{$$init_data{allowCredentials_b64}}, to_base64_type($$exCred{credential_id}, 'main'); # exCred is stored base64url, not base64. convert!
                    }
                }

                $$init_data{rpId} = $hostname;
                $$init_data{userVerification} = 'discouraged';
                $$init_data{timeout} = get_factor_flag($factor => $purpose => 'period')->value * 1000;

                # gen_random_byte_b64 returns main-standard base64, not url
                $$init_data{challenge_b64} = $e->json_query({
                    from => ['evergreen.gen_random_bytes_b64', get_factor_flag($factor => $purpose => 'digits')->value]
                })->[0]->{'evergreen.gen_random_bytes_b64'};
            }
        }

        return ($init_data, $otp_parts) if wantarray;
        return $init_data;
    }

    return undef;
}

sub send_otp_factor_challenge {
    my $usr = shift;
    my $factor = shift;
    my $purpose = shift || 'mfa';
    my $otp_parts = shift;

    if (!$otp_parts) {
        my $otp_uri = new_editor()->json_query({ from => [ 'actor.otpauth_uri' => $usr->id, $factor, $purpose ] })->[0];
        return undef unless ($otp_uri and $$otp_uri{'actor.otpauth_uri'});

        $otp_parts = unescape_otp_hash(Pass::OTP::URI::parse($$otp_uri{'actor.otpauth_uri'}));
    }

    my $otp_code = Pass::OTP::otp(%$otp_parts);
    return undef unless $otp_code;

    # either sms or email
    my $hook = "$purpose.send_$factor";
    my $user_data = {
        issuer   => $$otp_parts{issuer},
        otp_code => $otp_code
    };

    if ($factor eq 'email') {
        # send email to token holder's otpauth-uri email address
        $$user_data{email} = $$otp_parts{email}
    } elsif ($factor eq 'sms') {
        # send sms, via email, to token holder's otpauth-uri phone+carrier
        $$user_data{phone} = $$otp_parts{phone};
        $$user_data{carrier} = $$otp_parts{carrier};
    }

    return $U->fire_object_event( undef, $hook, $usr, $usr->ws_ou, undef, $user_data ) ? 1 : 0;
}

__PACKAGE__->register_method(
    method    => "mfa_ptoken_validate",
    api_name  => "open-ils.auth_mfa.process.validate",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/MFA validation hook, params other than the token and factor are factor-specific/,
        return => {
            desc => "Object containing at least the following keys: \n".
                    "  success  (bool; undef means unknown, 0 means fail, >0 means completed success, <0 means incomplete success (factor may need to do more))\n".
                    "  now      (current time)\n".
                    "  factor   (factor tested)\n".
                    "  token    (token tested)\n".
                    "  upgraded (bool; was the token upgraded)\n".
                    "  activity (bool; MFA activity was recorded)\n".
                    "Factors can add more keys",
            type => "object"
        }
    }
);
sub mfa_ptoken_validate {
    _init();
    my $self = shift;
    my $client = shift;
    my $token = shift;
    my $factor = shift;

    # pre-flight checks
    return 0 unless (enabled() and $token); # no token, or not enabled, no MFA
    my ($token_factors) = $self->method_lookup('open-ils.auth_mfa.token_factors.configured.provisional')->run($token);
    return 0 unless defined $token_factors; # returns undef for "not even allowed"
    return 0 unless (grep { $factor eq $_ } @$token_factors); # unconfigured or unknown factor

    # The test! Factors could have more than one step in their validation test, so they can coordinate state as appropriate via the %extra hash)
    my ($success_flag, $extra, $data) = $factor_validators{$factor}{mfa}->($factor, 'mfa', $token, @_);
    $extra ||= {};

    my $token_upgraded = 0;
    my $activity = 0;

    # positive means "complete and validated", negative means "partially validated, not yet failed", zero means failure
    if (defined $success_flag and $success_flag > 0) {
        if ($token_upgraded = upgrade_session($token)) {
            $success_flag = undef unless ($activity = record_mfa_validation($token, $factor, $data));
        } else {
            $success_flag = undef; 
        }
    }

    # that's it for now.
    my %result = (
        %$extra,
        upgraded => $token_upgraded,
        activity => $activity,
        success  => $success_flag, # undef means "something bad happened"
        now      => time,
        factor   => $factor,
        token    => $token
    );

    return \%result;
}

__PACKAGE__->register_method(
    method    => "mfa_ptoken_upgrade",
    api_name  => "open-ils.auth_mfa.provisional_upgrade",
    api_level => 1,
    argc      => 1,
    signature => {
        desc => q/MFA token upgrade, when allowed/,
        return => {
            desc => "True on success, false otherwise",
            type => "bool"
        }
    }
);
sub mfa_ptoken_upgrade {
    _init();
    my $self = shift;
    my $client = shift;
    my $token = shift;

    # pre-flight checks
    return 0 unless (enabled() and $token); # no token, or not enabled, no MFA
    my ($is_required) = $self->method_lookup('open-ils.auth_mfa.required_for_token.provisional')->run($token);
    return 0 if $is_required;

    return upgrade_session($token);
}

$factor_validators{webauthn}{mfa} = sub { # only works with a provisional token!
    my $factor = shift;
    my $purpose = shift;
    my $token = shift;
    my $input = shift;

    my $provisional_session = $U->check_provisional_session($token);
    return 0 unless $provisional_session;
    $logger->info("MFA $factor: validate -> have session");

    my $usr = $provisional_session->{userobj};
    return 0 unless $usr;
    $logger->info("MFA $factor: validate -> have user");

    return webauthn_validation_core($usr, $factor, $purpose, $token, $input);
};

sub webauthn_validation_core {
    my $usr = shift;
    my $factor = shift;
    my $purpose = shift;
    my $token = shift;
    my $input = shift;

    my $init_data = $cache->get_cache("$purpose.$factor.$token.validate_init_cache");
    return 0 unless ($init_data);
    $logger->info("MFA $factor: validate -> have init_data");

    if ($input and !ref($input)) { # got a hostname, step one
        $logger->info("MFA $factor: validate -> input exists but is not an object, must be hostname: $input");

        my $hostname = $input;
        if (my $configured_RP = get_factor_flag($factor => $purpose => 'domain')->value) {
            # Setting webauthn.$purpose.domain to the base domain allows one credential
            # to cover all hostname-deliniated login locations as in a consortial setup
            $hostname = $configured_RP if ($hostname =~ /$configured_RP$/i);
        }
        return 0 unless ($hostname eq $$init_data{rpId}); # make sure they're asking for the current init'd RP
        $logger->info("MFA $factor: validate -> RP: $hostname");

        return (-1, $init_data);
    }

    return undef unless ($input and ref($input) eq 'HASH');
    $logger->info("MFA $factor: validate -> seconds stage, have credential object");

    my $otp_uri = new_editor()->json_query({ from => [ 'actor.otpauth_uri' => $usr->id, $factor, $purpose] })->[0];
    return undef unless ($otp_uri and $$otp_uri{'actor.otpauth_uri'});

    # credential id is delivered as base64url
    my $otp_parts = unescape_otp_hash(Pass::OTP::URI::parse($$otp_uri{'actor.otpauth_uri'}));
    my $cred = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{$$input{id}});
    return undef unless ($cred);
 
    my $clientData = OpenSRF::Utils::JSON->JSON2perl(decode_base64($$input{clientDataJSON_b64}));

    my $webauthn_rp = Authen::WebAuthn->new(
        rp_id  => $$init_data{rpId},
        origin => $$clientData{origin}
    );
 
    my $validation_result = eval {
        $webauthn_rp->validate_assertion(
            challenge_b64          => to_base64_type($$init_data{challenge_b64}, 'url'),
            requested_uv           => $$init_data{userVerification},
            client_data_json_b64   => to_base64_type($$input{clientDataJSON_b64}, 'url'),
            authenticator_data_b64 => to_base64_type($$input{authenticatorData_b64}, 'main'),
            signature_b64          => to_base64_type($$input{signature_b64}, 'url'),
            extension_results      => $$input{extension_results},
            credential_pubkey_b64  => to_base64_type($$cred{credential_pubkey}, 'url'),
            stored_sign_count      => 0 # disable signature count checks
        )
    };
    if ($@) {
        $logger->error("Error validating $factor authentication: $@");
        return 0;
    }

    return (1, undef, $validation_result);
}

$factor_validators{totp}{mfa} = sub { # only works with a provisional token!
    my $factor = shift;
    my $purpose = shift;
    my $token = shift;
    my $user_code = shift; # TOTP factor (and similar) expects a proof value from the user

    my $provisional_session = $U->check_provisional_session($token);
    return 0 unless $provisional_session;

    my $usr = $provisional_session->{userobj};
    return 0 unless $usr;

    return totp_auth_core( $factor => $purpose => $usr->id => $user_code);
};

# These all use the same as totp->mfa, for now.
$factor_validators{totp}{login}  = $factor_validators{totp}{mfa};
$factor_validators{email}{mfa}   = $factor_validators{totp}{mfa};
$factor_validators{email}{login} = $factor_validators{totp}{mfa};
$factor_validators{sms}{mfa}     = $factor_validators{totp}{mfa};
$factor_validators{sms}{login}   = $factor_validators{totp}{mfa};

sub totp_auth_core { # needs just factor, purpose, user id, and user input, so can be used for real or provisional sessions
    my $factor = shift;
    my $purpose = shift;
    my $usr = shift;
    my $input = shift;
    $input =~ s/\D//g; # retain only digits from the user

    # get the user's otpauth URI from the database
    my $e = new_editor(xact => 1);
    my $otp_uri = $e->json_query({ from => [ 'actor.otpauth_uri' => $usr, $factor, $purpose ] })->[0];
    return rollback_and_zero($e, "totp_auth_core: no URI returned by database function") unless $otp_uri and $$otp_uri{'actor.otpauth_uri'};

    my %otp_config = Pass::OTP::URI::parse($$otp_uri{'actor.otpauth_uri'});
    my $fuzziness_width = int($factors{$factor}{$purpose}{fuzziness});

    for my $fuzziness ( -$fuzziness_width .. $fuzziness_width ) {
        $otp_config{'start-time'} = $otp_config{period} * $fuzziness;
        my $otp_code = Pass::OTP::otp(%otp_config);
        if ($otp_code eq $input) {
            $e->commit;
            return 1;
        } else {
            $logger->warn("totp_auth_core: OTP code [$otp_code] at fuzziness [$fuzziness] does not match user input [$input]");
        }
    }

    return rollback_and_zero($e, "totp_auth_core: test never passed, fuzziness: $fuzziness_width");
}

sub rollback_and_undef {
    my $e = shift;
    my $warning = shift;
    $logger->warn($warning) if $warning;
    $e->rollback;
    return undef;
}

sub rollback_and_zero {
    my $e = shift;
    my $warning = shift;
    $logger->warn($warning) if $warning;
    $e->rollback;
    return 0;
}

sub upgrade_session {
    my $token = shift;

    my $event =$U->simplereq(
        'open-ils.auth_internal',
        'open-ils.auth_internal.session.upgrade_provisional',
        $token
    );

    my $code = $U->event_code($event);
    return 1 if (defined $code and $code == 0); # code is '0', i.e. SUCCESS

    $logger->warn("MFA could not upgrade provisional session: ". $token);
    return 0; # upgrade failed!
}

# session must be upgraded before calling this
sub record_mfa_validation {
    my $token = shift;
    my $who = shift;
    my $data = shift;

    my $e = new_editor(authtoken => $token, xact => 1);
    return rollback_and_zero($e) unless $e->checkauth;

    my $rows = $e->json_query({
        from => [
            'actor.insert_usr_activity',
            $e->requestor->id,
            $who,
            'confirm',
            OpenSRF::AppSession->ingress,
            OpenSRF::Utils::JSON->perl2JSON($data)
        ]
    });

    if ($rows) { # call succeeded
        if (@$rows) { # ... and returned a row
            $e->commit;
            return 1;
        } else {
            $logger->warn("MFA is not fully configured: Likely missing 'confirm' ewhat row in config.usr_activity_type");
        }
    } else {
        $logger->warn("MFA could not record user activity");
    }

    return rollback_and_zero($e);
}

__PACKAGE__->register_method(
    method    => "mfa_ptoken_complete",
    api_name  => "open-ils.auth_mfa.process.complete",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/MFA completion hook, params other than the (real, upgraded) token and factor are factor-specific/,
        return => {
            desc => "True if successful, false for any error",
            type => "bool"
        }
    }
);
sub mfa_ptoken_complete {
    _init();
    my $self = shift;
    my $client = shift;
    my $token = shift;
    my $factor = shift;

    # pre-flight checks
    return 0 unless (enabled() and $token); # no token, or not enabled, no MFA

    # calling non-provisional version, since we are post-session-upgrade
    my ($token_factors) = $self->method_lookup('open-ils.auth_mfa.token_factors.configured')->run($token);
    return 0 unless defined $token_factors; # returns undef for "not even allowed"
    return 0 unless (grep { $factor eq $_ } @$token_factors); # unconfigured or unknown factor}

    # nothing to do for these
    return 1 if grep { $factor eq $_ } qw/hotp totp static sms email webauthn/;

    # that's it for now.
    return 0;
}

__PACKAGE__->register_method(
    method    => "mfa_factor_config",
    api_name  => "open-ils.auth_mfa.token_factor.configure.init",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/Request factor-specific MFA setup data from EG for the token holder/,
        return => {
            desc => "Data if successful, undef for any error",
            type => "object"
        }
    }
);
__PACKAGE__->register_method(
    method    => "mfa_factor_config",
    api_name  => "open-ils.auth_mfa.token_factor.configure.init.provisional",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/Request factor-specific MFA setup data from EG for the provisional token holder/,
        return => {
            desc => "Data if successful, undef for any error",
            type => "object"
        }
    }
);
__PACKAGE__->register_method(
    method    => "mfa_factor_config",
    api_name  => "open-ils.auth_mfa.token_factor.configure.complete",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/Provide factor-specific MFA setup data to EG for the token holder/,
        return => {
            desc => "Data if successful, undef for any error",
            type => "bool"
        }
    }
);
__PACKAGE__->register_method(
    method    => "mfa_factor_config",
    api_name  => "open-ils.auth_mfa.token_factor.configure.complete.provisional",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/Provide factor-specific MFA setup data to EG for the provisional token holder/,
        return => {
            desc => "Data if successful, undef for any error",
            type => "bool"
        }
    }
);
__PACKAGE__->register_method(
    method    => "mfa_factor_config",
    api_name  => "open-ils.auth_mfa.token_factor.configure.remove",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/Remove a configured factor mapping for the token holder/,
        return => {
            desc => "Success or failure, except for webauthn -> First call: validation data; second call: True if successful, False otherwise",
            type => "bool|object"
        }
    }
);
__PACKAGE__->register_method(
    method    => "mfa_factor_config",
    api_name  => "open-ils.auth_mfa.token_factor.configure.remove.provisional",
    api_level => 1,
    argc      => 2,
    signature => {
        desc => q/Remove a configured factor mapping for the provisional token holder/,
        return => {
            desc => "Success or failure, except for webauthn -> First call: validation data; second call: True if successful, False otherwise",
            type => "bool|object"
        }
    }
);
sub mfa_factor_config {
    _init();
    my $self = shift;
    my $client = shift;
    my $token = shift;
    my $factor = shift;
    my @incoming_data = @_;

    my $init = ($self->api_name =~ /init/) ? 1 : 0;
    my $complete = ($self->api_name =~ /complete/) ? 1 : 0;
    my $remove = ($self->api_name =~ /remove/) ? 1 : 0;
    my $provisional = ($self->api_name =~ /provisional$/) ? 1 : 0;
    my $purpose = 'mfa'; # TODO add login option later via api_name

    my $e = new_editor(xact=>1);

    # pre-flight checks
    return undef unless (enabled() and $token); # no token, or not enabled, no MFA
    return undef if ($provisional and $remove); # can't remove in provisional state

    my ($usr, $token_factors, $required);
    if ($provisional) {
        my ($allowed) = $self->method_lookup('open-ils.auth_mfa.allowed_for_token.provisional')->run($token);
        return undef unless $allowed;

        ($token_factors) = $self->method_lookup('open-ils.auth_mfa.token_factors.available.provisional')->run($token);
        my $provisional_session = $U->check_provisional_session($token);
        $usr = $$provisional_session{userobj};

        ($required) = $self->method_lookup('open-ils.auth_mfa.required_for_token.provisional')->run($token);
    } else {
        my ($allowed) = $self->method_lookup('open-ils.auth_mfa.allowed_for_token')->run($token);
        return undef unless $allowed;

        ($token_factors) = $self->method_lookup('open-ils.auth_mfa.token_factors.available')->run($token);
        $usr = $U->check_user_session($token);

        ($required) = $self->method_lookup('open-ils.auth_mfa.required_for_token')->run($token);
    }

    return undef unless ref $token_factors; # returns undef for "not even allowed"
    return undef unless (grep { $factor eq $_ } @$token_factors); # unavailable or unknown factor
    return undef unless $usr; # no session, no MFA

    my ($configured_factors) = $provisional ?
        $self->method_lookup('open-ils.auth_mfa.token_factors.configured.provisional')->run($token) :
        $self->method_lookup('open-ils.auth_mfa.token_factors.configured')->run($token);

    return undef if ($provisional and $required and $configured_factors and @$configured_factors); # can't add in provisional state once you have at least one

    $logger->info("MFA factor configuration -".
         " mode: " . ($complete ? 'complete' : ($remove ? 'remove' : 'init') ).
        "; token: $token".
        "; factor: $factor"
    );


    # now the meat of the function

    if ($remove and is_otp_based($factor)) { # in remove mode

        my $success = 0;
        if ($factor eq 'webauthn') {
            my $removal_init_data;
            ($success, $removal_init_data) = webauthn_validation_core($usr, $factor, 'mfa', $token, @incoming_data);

            if ($success < 0) { # stage 1
                $$removal_init_data{success} = -1;
                return $removal_init_data;
            }

            @incoming_data = ();
        } else {
            $success = totp_auth_core($factor => $purpose => $usr->id => @incoming_data); # confirm they know the secret
        }

        if ($success) {
            # attempt to remove the factor mapping generally
            my $success = remove_factor_mapping_for_user($factor => $purpose => $usr->id);

            # if that works, attempt to remove the password entry that we use for otpauth URI generation
            return remove_otpauth_password_entry_for_factor($factor => $purpose => $usr->id => @incoming_data) if ($success);
        }

        return 0;
    }

    my $init_data = {};
    my $additional_init_params = '';

    if ($init) { # in init mode setup
        # create hstore containing email or phone/carrier
        # so we can pass that to the otpauth json_query
        if ($factor eq 'email') {
            return undef unless (Email::Valid->address($incoming_data[0]));

            $additional_init_params = make_hstore($e, email => $incoming_data[0]);
        } elsif ($factor eq 'sms') {
            return undef unless ($incoming_data[0] and ref($incoming_data[0]) eq 'HASH');

            my $sms_data = $incoming_data[0];
            return undef unless ($$sms_data{phone} and $$sms_data{carrier});
            return if (ref($$sms_data{phone}) or ref($$sms_data{carrier}));

            $additional_init_params = make_hstore($e, phone => $$sms_data{phone}, carrier => $$sms_data{carrier});
        } elsif ($factor eq 'webauthn') {
            return undef unless ($incoming_data[0] and !ref($incoming_data[0]));

            my $hostname = $incoming_data[0]; # they need to tell us what they see
            return undef unless ($hostname);

            if (my $configured_RP = get_factor_flag($factor => $purpose => 'domain')->value) {
                # Setting webauthn.$purpose.domain to the base domain allows one credential
                # to cover all hostname-deliniated login locations as in a consortial setup
                $hostname = $configured_RP if ($hostname =~ /$configured_RP$/i);
            }
            return undef unless ($hostname);

            $$init_data{rp} = {id => $hostname};
        }
    }

    if (is_otp_based($factor)) {
        # in either init or complete mode, get the user's otpauth URI from the database
        my $otp_uri = $e->json_query({ from => [ 'actor.otpauth_uri' => $usr->id, $factor, $purpose, $additional_init_params ] })->[0];
        if ($otp_uri and $$otp_uri{'actor.otpauth_uri'}) {
            my $otp_parts = unescape_otp_hash(Pass::OTP::URI::parse($$otp_uri{'actor.otpauth_uri'}));
            
            if ($init) { # in init mode
                if ($factor =~ /^[ht]otp$/) {
                    # return the URI for totp/hotp
                    $init_data = { uri => $$otp_uri{'actor.otpauth_uri'} };
                } elsif ($factor eq 'email') {
                    $init_data = {
                        email => $$otp_parts{email},
                        sent  => send_otp_factor_challenge($usr, $factor, $purpose, $otp_parts)
                    };
                } elsif ($factor eq 'sms') {
                    $init_data = {
                        phone   => $$otp_parts{phone},
                        carrier => $$otp_parts{carrier},
                        sent    => send_otp_factor_challenge($usr, $factor, $purpose, $otp_parts)
                    };
                } elsif ($factor eq 'webauthn') {
                    $$init_data{pubKeyCredParams} = [
                        { alg => -7,   type => 'public-key'}, # most authenticators
                        { alg => -257, type => 'public-key'}, # windows hello
                        { alg => -8,   type => 'public-key'}  # some newer yubi keys
                    ];
                    $$init_data{rp}{name} = get_factor_flag($factor => $purpose => 'issuer')->value;

                    $$init_data{challenge_b64} = $e->json_query({
                        from => ['evergreen.gen_random_bytes_b64', get_factor_flag($factor => $purpose => 'digits')->value]
                    })->[0]->{'evergreen.gen_random_bytes_b64'};

                    $$init_data{attestation} = 'none';
                    $$init_data{authenticatorSelection} = {
                        authenticatorAttachment => 'cross-platform',
                        requireResidentKey      => 0,
                        userVerification        => 'discouraged'
                    };

                    $$init_data{timeout} = get_factor_flag($factor => $purpose => 'period')->value * 1000;
                    $$init_data{user} = {
                        displayName => $usr->usrname,
                        name => $usr->usrname,
                        id => $$otp_parts{secret}
                    };

                    if (!get_factor_flag($factor => $purpose => 'multicred')) {
                        $$init_data{excludeCredentials_b64} = [];
                        if (my $RPs = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{RPs})) {
                            if (my ($known_RP) = grep { $_ eq $$init_data{rp}{id} } @$RPs) {
                                if (my $known_creds = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{$known_RP})) {
                                    for my $credId (@$known_creds) { # looping through these makes sure we actually have the credential data, not just the id
                                        if (my $exCred = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{$credId})) {
                                            push @{$$init_data{excludeCredentials_b64}}, to_base64_type($$exCred{credential_id}, 'main');
                                        }
                                    }
                                }
                            }
                        }
                    }

                    $cache->put_cache(
                        "mfa.$factor.$token.config_init_cache",
                        $init_data,
                        get_factor_flag($factor => $purpose => 'period')->value * 2
                    );
                }
                $e->commit;
                return $init_data;
            }

            # in complete mode, here. check user input
            my $success = 0;
            if ($factor eq 'webauthn') {
                my $config_init_data = $cache->get_cache("mfa.$factor.$token.config_init_cache");
                return 0 unless ($config_init_data and ref($config_init_data) eq 'HASH');

                my $credential = $incoming_data[0];
                return 0 unless ($credential and ref($credential) eq 'HASH');

                my $clientData = OpenSRF::Utils::JSON->JSON2perl(decode_base64($$credential{clientDataJSON_b64}));
                my $webauthn_rp = Authen::WebAuthn->new(
                    rp_id  => $$config_init_data{rp}{id},
                    origin => $$clientData{origin}
                );
 
                my $registration_result = eval {
                    $webauthn_rp->validate_registration(
                        challenge_b64          => to_base64_type($$config_init_data{challenge_b64}, 'url'),
                        requested_uv           => $$config_init_data{authenticatorSelection}{userVerification} ,
                        client_data_json_b64   => to_base64_type($$credential{clientDataJSON_b64}, 'url'),
                        attestation_object_b64 => to_base64_type($$credential{attestationObject_b64}, 'url')
                    )
                };
                if ($@) {
                    $logger->error("Error validating $factor registration: $@");
                    return 0;
                }

                # success! record it
                my $RPs = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{RPs}) || [];
                my $new_rp = $$config_init_data{rp}{id};
                push(@$RPs, $new_rp) unless (grep {$_ eq $new_rp} @$RPs);

                my $cred_list = OpenSRF::Utils::JSON->JSON2perl($$otp_parts{$new_rp}) || [];
                my $new_cred = $$registration_result{credential_id}; 
                return undef if (grep {$_ eq $new_cred} @$cred_list); # whoa bud! can't re-reg a pubkey, need a new one
                return undef if (!get_factor_flag($factor => $purpose => 'multicred') and scalar(@$cred_list)); # no new ones allowed

                push(@$cred_list, $new_cred);

                $additional_init_params = make_hstore($e,
                    RPs => OpenSRF::Utils::JSON->perl2JSON($RPs),
                    $new_rp => OpenSRF::Utils::JSON->perl2JSON($cred_list),
                    $new_cred => OpenSRF::Utils::JSON->perl2JSON($registration_result)
                );

                my $updated_otp_uri = $e->json_query({
                    from => [ 'actor.otpauth_uri' => $usr->id, $factor, $purpose, $additional_init_params ]
                })->[0];

                $success++ if ($updated_otp_uri and $$updated_otp_uri{'actor.otpauth_uri'});
            } elsif (totp_auth_core($factor => $purpose => $usr->id => @incoming_data)) {
                $success++;
            }

            $e->commit if ($success);

            unless (grep {$_ eq $factor} @$configured_factors) {
                $logger->info("MFA factor configuration - factor $factor not yet configured for user ". $usr->id);
                my $mapping_success = add_factor_mapping_for_user($factor => $purpose => $usr->id);
                if ($mapping_success) {
                    $logger->info("MFA factor configuration - factor $factor newly configured for user ". $usr->id);
                } else {
                    $logger->info("MFA factor configuration - factor $factor COULD NOT be configured for user ". $usr->id);
                }
                return $mapping_success;
            }

            $logger->info("MFA factor configuration - factor $factor already configured for user ". $usr->id);
            return $success; # already configured, in "complete" mode
        }
    }

    return undef;
}

sub uri_unescape {
    my $input = shift;
    return $input unless $input;
    $input =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    Encode::decode('utf-8',$input);
    return $input;
}

sub unescape_otp_hash {
    my %hash = @_;
    my $newhash = {};
    for my $key (keys %hash) {
        $$newhash{uri_unescape($key)} = uri_unescape($hash{$key});
    }

    return $newhash;
}

sub is_otp_based {
    my $factor = shift;
    return 1 if (grep { $factor eq $_} qw/totp hotp email sms webauthn/);
    return 0;
}

sub make_hstore {
    my $e = shift;
    my %hash = @_;

    my $out = join ',', map {
        $e->json_query({
            from => [ hstore => $_ => $hash{$_} ]
        })->[0]->{hstore}
    } keys %hash;

    $logger->info('MFA: make_hstore => ['.$out.']');
    return $out;
}

sub add_factor_mapping_for_user {
    my $factor = shift; # factor name
    my $purpose = shift;
    my $usr = shift; # user id

    my $new_map = Fieldmapper::actor::usr_mfa_factor_map->new;
    $new_map->usr($usr);
    $new_map->purpose($purpose);
    $new_map->factor($factor);

    my $e = new_editor(xact=>1);
    $e->create_actor_usr_mfa_factor_map($new_map);
    return $e->commit ? 1 : 0;
}

sub remove_factor_mapping_for_user {
    my $factor = shift; # factor name
    my $purpose = shift;
    my $usr = shift; # user id

    my $e = new_editor(xact=>1);
    my $mappings = $e->search_actor_usr_mfa_factor_map(
        {usr => $usr, factor => $factor, purpose => $purpose}
    );

    return rollback_and_zero($e) if (!@$mappings);

    $e->delete_actor_usr_mfa_factor_map($$mappings[0]);
    return $e->commit ? 1 : 0;
}

sub remove_otpauth_password_entry_for_factor {
    my $factor = shift; # factor name
    my $purpose = shift;
    my $usr = shift; # user id
    my $proof = shift;

    my $e = new_editor(xact=>1);
    my $r = $e->json_query({ from => [ 'actor.remove_otpauth_uri' => $usr, $factor, $purpose, $proof ] })->[0];
    return rollback_and_zero($e) if (!$U->is_true($$r{'actor.remove_otpauth_uri'}));
    return $e->commit ? 1 : 0;
}

1;
