package OpenILS::WWW::PasswordReset;

# Copyright (C) 2010 Laurentian University
# Dan Scott <dscott@laurentian.ca>
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

use strict; use warnings;

use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;
use Template;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::AppSession;

use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

my $log = 'OpenSRF::Utils::Logger';
my $U = 'OpenILS::Application::AppUtils';

my ($bootstrap, $actor, $templates);
my $i18n = {};
my $init_done = 0; # has child_init been called?

sub import {
    my $self = shift;
    $bootstrap = shift;
}

sub child_init {
    OpenSRF::System->bootstrap_client( config_file => $bootstrap );
    
    my $conf = OpenSRF::Utils::SettingsClient->new();
    my $idl = $conf->config_value("IDL");
    Fieldmapper->import(IDL => $idl);
    $templates = $conf->config_value("dirs", "templates");
    $actor = OpenSRF::AppSession->create('open-ils.actor');
    load_i18n();
    $init_done = 1;
    return Apache2::Const::OK;
}

sub password_reset {
    my $apache = shift;

    child_init() unless $init_done;

    return Apache2::Const::DECLINED if (-e $apache->filename);

    $apache->content_type('text/html');

	my $cgi = new CGI;
    my $ctx = {};

    $ctx->{'uri'} = $apache->uri;

    # Get our locale from the URL
    (my $locale = $apache->path_info) =~ s{^.*?/([a-z]{2}-[A-Z]{2})/.*?$}{$1};
    if (!$locale) {
        $locale = 'en-US';
    }

    # If locale exists, use it; otherwise fall back to en-US
    if (exists $i18n->{$locale}) {
        $ctx->{'i18n'} = $i18n->{$locale};
    } else {
        $ctx->{'i18n'} = $i18n->{'en-US'};
    }

    my $tt = Template->new({
        INCLUDE_PATH => $templates
    }) || die "$Template::ERROR\n";

    # Get our UUID: if no UUID, then display barcode / username / email prompt
    (my $uuid = $apache->path_info) =~ s{^/$locale/([^/]*?)$}{$1};
    $logger->info("Password reset: UUID = $uuid");

    if (!$uuid) {
        request_password_reset($apache, $cgi, $tt, $ctx);
    } else {
        reset_password($apache, $cgi, $tt, $ctx, $uuid);
    }
}

sub reset_password {
    my ($apache, $cgi, $tt, $ctx, $uuid) = @_;

    my $password_1 = $cgi->param('pwd1');
    my $password_2 = $cgi->param('pwd2');

    $ctx->{'title'} = $ctx->{'i18n'}{'TITLE'};
    $ctx->{'password_prompt'} = $ctx->{'i18n'}{'PASSWORD_PROMPT'};
    $ctx->{'password_prompt2'} = $ctx->{'i18n'}{'PASSWORD_PROMPT2'};

    # In case non-matching passwords slip through our funky Web interface
    if ($password_1 and $password_2 and ($password_1 ne $password_2)) {
        $ctx->{'status'} = {
            style => 'error',
            msg => $ctx->{'i18n'}{'NO_MATCH'}
        };
        $tt->process('password-reset/reset-form.tt2', $ctx)
            || die $tt->error();
        return Apache2::Const::OK;
    }

    if ($password_1 and $password_2 and ($password_1 eq $password_2)) {
        my $response = $actor->request('open-ils.actor.patron.password_reset.commit', $uuid, $password_1)->gather();
        if (ref($response) && $response->{'textcode'}) {

            if ($response->{'textcode'} eq 'PATRON_NOT_AN_ACTIVE_PASSWORD_RESET_REQUEST') {
                $ctx->{'status'} = { 
                    style => 'error',
                    msg => $ctx->{'i18n'}{'NOT_ACTIVE'}

                };
            }
            if ($response->{'textcode'} eq 'PATRON_PASSWORD_WAS_NOT_STRONG') {
                $ctx->{'status'} = { 
                    style => 'error',
                    msg => $ctx->{'i18n'}{'NOT_STRONG'}

                };
            }
            $tt->process('password-reset/reset-form.tt2', $ctx)
                || die $tt->error();
            return Apache2::Const::OK;
        }
        $ctx->{'status'} = { 
            style => 'success',
            msg => $ctx->{'i18n'}{'SUCCESS'}
        };
    }

    # Either the password change was successful, or this is their first time through
    $tt->process('password-reset/reset-form.tt2', $ctx)
        || die $tt->error();

    return Apache2::Const::OK;
}

# Load our localized strings - lame, need to convert to Locale::Maketext
sub load_i18n {
    foreach my $string_bundle (glob("$templates/password-reset/strings.*")) {
        open(I18NFH, '<', $string_bundle);
        (my $locale = $string_bundle) =~ s/^.*\.([a-z]{2}-[A-Z]{2})$/$1/;
        $logger->debug("Loaded locale [$locale] from file: [$string_bundle]");
        while(<I18NFH>) {
            my ($string_id, $string) = ($_ =~ m/^(.+?)=(.*?)$/);
            $i18n->{$locale}{$string_id} = $string;
        }
        close(I18NFH);
    }
}

sub request_password_reset {
    my ($apache, $cgi, $tt, $ctx) = @_;

    my $barcode = $cgi->param('barcode');
    my $username = $cgi->param('username');
    my $email = $cgi->param('email');

    if (!($barcode or $username or $email)) {
        $ctx->{'status'} = {
            style => 'plain',
            msg => $ctx->{'i18n'}{'IDENTIFY_YOURSELF'}
        };
        $tt->process('password-reset/request-form.tt2', $ctx)
            || die $tt->error();
        return Apache2::Const::OK;
    } elsif ($barcode) {
        my $response = $actor->request('open-ils.actor.patron.password_reset.request', 'barcode', $barcode)->gather();
        $ctx->{'status'} = {
            style => 'plain',
            msg => $ctx->{'i18n'}{'REQUEST_SUCCESS'}
        };
        # Hide form
        $tt->process('password-reset/request-form.tt2', $ctx)
            || die $tt->error();
        return Apache2::Const::OK;
    } elsif ($username) {
        my $response = $actor->request('open-ils.actor.patron.password_reset.request', 'username', $username)->gather();
        $ctx->{'status'} = {
            style => 'plain',
            msg => $ctx->{'i18n'}{'REQUEST_SUCCESS'}
        };
        # Hide form
        $tt->process('password-reset/request-form.tt2', $ctx)
            || die $tt->error();
        return Apache2::Const::OK;
    }
}

1;

# vim: et:ts=4:sw=4
