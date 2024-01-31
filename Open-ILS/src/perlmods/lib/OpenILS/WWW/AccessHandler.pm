package OpenILS::WWW::AccessHandler;
use strict; use warnings;

# Apache Requirements
use Apache2::Const -compile => qw(:common HTTP_OK HTTP_FORBIDDEN HTTP_MOVED_TEMPORARILY HTTP_MOVED_PERMANENTLY);
use Apache2::RequestRec;
use Apache2::URI;

# OpenSRF requirements
use OpenSRF::System;

# Other requirements
use URI::Escape;

# Auth Handler
sub handler {
    my ($r) = @_;

    # Configuration options

    # URL to redirect to for login
    my $lurl = $r->dir_config('OILSAccessHandlerLoginURL') || '/eg/opac/login';
    # Redirection variable to come "back" from the previous URL
    my $lurlvar = $r->dir_config('OILSAccessHandlerLoginURLRedirectVar') || 'redirect_to';
    # No access page? If not set, just return forbidden.
    my $failurl = $r->dir_config('OILSAccessHandlerFailURL');
    # Required permission (if set)
    my $userperm = $r->dir_config('OILSAccessHandlerPermission');
    # Need to be in good standing?
    my $userstanding = $r->dir_config('OILSAccessHandlerGoodStanding') || 0;
    # Required org unit (if set)
    my $userou = $r->dir_config('OILSAccessHandlerHomeOU');
    # OU for permission/standing checks, if not set use home OU
    my $checkou = $r->dir_config('OILSAccessHandlerCheckOU');
    # Set referrer based on OU Setting?
    my $referrersetting = $r->dir_config('OILSAccessHandlerReferrerSetting');

    my $url = $r->construct_url();

    # push everyone to the secure site
    if ($url =~ /^http:/o) {
        my $target = $r->construct_url($r->unparsed_uri);
        $target =~ s/^http:/https:/o;
        $r->headers_out->set(Location => $target);
        return Apache2::Const::HTTP_MOVED_PERMANENTLY;
    }

    # We could use CGI....but that creates issues if post data may be submitted
    my $auth_ses = ($r->headers_in->get('Cookie') =~ /(?:^|\s)ses=([^;]*)/)[0];
    $auth_ses = ($r->headers_in->get('Cookie') =~ /(?:^|\s)eg.auth.token=%22([^;]*)%22/)[0] unless $auth_ses;
    my $user = _verify_login($auth_ses);

    if (!defined($user)) {
        my $redirect = $r->construct_url($r->unparsed_uri);
        my $target = $r->construct_url($lurl) . '?' . $lurlvar . '=' . uri_escape($redirect);
        $target =~ s/^http:/https:/o; # This should never be needed due to the redirect above, but better safe than sorry
        $r->headers_out->set(Location => $target);
        # Lets not cache this either, just in case.
        $r->headers_out->set('Cache-Control' => 'no-cache, no-store, must-revalidate');
        $r->headers_out->set(Pragma => 'no-cache');
        $r->headers_out->set(Expires => 0);
        return Apache2::Const::HTTP_MOVED_TEMPORARILY;
    }

    # Convert check OU from shortname, if needed
    $checkou = _get_org_id($checkou);

    # If we have no check OU at this point, use the user's home OU
    $checkou ||= $user->home_ou;

    my $failed = 0;

    if ($userperm) {
        my @permissions = split(/\s*[ ,]\s*/, $userperm);
        $failed++ unless _verify_permission($auth_ses, $user, $checkou, \@permissions);
    }
    if (!$failed && $userstanding) {
        $failed++ unless _verify_standing($user);
    }
    if (!$failed && $userou) {
        $failed++ unless _verify_home_ou($user, $userou);
    }

    # If we failed one of the above checks they aren't allowed in
    if ($failed > 0) {
        if ($failurl) {
            my $target = $r->construct_url($failurl);
            $r->headers_out->set(Location => $target);
            return Apache2::Const::HTTP_MOVED_TEMPORARILY;
        } else {
            return Apache2::Const::HTTP_FORBIDDEN;
        }
    }

    # Forced referrer for some referrer auth services?
    if ($referrersetting) {
        my $referrervalue = _get_ou_setting($referrersetting, $checkou);
        if ($referrervalue && $referrervalue->{value}) {
            $r->headers_in->set('Referer', $referrervalue->{value});
        }
    }

    # If we haven't thrown them out yet, let them through
    return Apache2::Const::OK;
}

# "Private" functions

# Verify our login
sub _verify_login {
    my ($token) = @_;
    return undef unless $token;

    my $user = OpenSRF::AppSession
        ->create('open-ils.auth')
        ->request('open-ils.auth.session.retrieve', $token)
        ->gather(1);

    if (ref($user) eq 'HASH' && $user->{ilsevent} == 1001) {
        return undef;
    }

    return $user if ref($user);
    return undef;
}

# OU Shortname to ID
sub _get_org_id {
    my ($org_identifier) = @_;
    # Does this look like a number?
    if ($org_identifier !~ '^[0-9]+$') {
        # Not a database id
        if ($org_identifier) { 
            # Look up org unit by shortname
            my $org_unit = OpenSRF::AppSession
                ->create('open-ils.actor')
                ->request('open-ils.actor.org_unit.retrieve_by_shortname', $org_identifier)
                ->gather(1);
            if ($org_unit && ref($org_unit) ne 'HASH') {
                # We appear to have an org unit! So return the ID.
                return $org_unit->id;
            }
        }
    } else {
        # Looks like a database ID, so leave it alone.
        return $org_identifier;
    }
    # If we have reached this point, assume that we found no useful ID.
    return undef;
}

# Verify home OU
sub _verify_home_ou {
    my ($user, $home_ou) = @_;
    my $org_tree = OpenSRF::AppSession
        ->create('open-ils.actor')
        ->request('open-ils.actor.org_tree.ancestors.retrieve', $user->home_ou)
        ->gather(1);
    if ($org_tree && ref($org_tree) ne 'HASH') {
        my %user_orgs;
        do {
            $user_orgs{$org_tree->id} = 1;
            if ($org_tree->children) {
                $org_tree = @{$org_tree->children}[0];
            } else {
                $org_tree = undef;
            }
        } while ($org_tree);

        my @home_ous = split(/\s*[ ,]\s*/,$home_ou);
        for my $cur_ou (@home_ous) {
            $cur_ou = _get_org_id($cur_ou);
            if ($user_orgs{$cur_ou}) {
                return 1;
            }
        }
    }
    return 0;
}

# Verify permission
sub _verify_permission {
    my ($token, $user, $org_unit, $permissions) = @_;

    my $failures = OpenSRF::AppSession
        ->create('open-ils.actor')
        ->request('open-ils.actor.user.perm.check', $token, $user->id, $org_unit, $permissions)
        ->gather(1);

    return !scalar(@$failures);
}

# Verify standing
sub _verify_standing {
    my ($user) = @_;

    # If barred you are not in good standing
    return 0 if $user->barred;
    # If inactive you are also not in good standing
    return 0 unless $user->active;

    # Possible addition: Standing Penalty Checks?

    return 1;
}

sub _get_ou_setting {
    my ($setting, $org_unit) = @_;

    my $value = OpenSRF::AppSession->create('open-ils.actor')
        ->request('open-ils.actor.ou_setting.ancestor_default', $org_unit, $setting)
        ->gather(1);

    return $value;
}

1;
