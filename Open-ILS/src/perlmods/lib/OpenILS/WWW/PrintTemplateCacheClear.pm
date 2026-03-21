package OpenILS::WWW::PrintTemplateCacheClear;

use warnings;
use strict;

use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::System;
use Apache2::Const -compile =>
    qw(OK FORBIDDEN HTTP_INTERNAL_SERVER_ERROR HTTP_BAD_REQUEST);
use CGI;

# This mod_perl handler allows users with the appropriate
# permissions to clear the Print Template cache for
# a given org unit.  Useful when they have made changes
# to one of the org unit's templates, and want everyone
# to stop using the stale cached version.

my $bs_config;
sub import {
    my $_self = shift;
    $bs_config = shift;
    return;
}

my $init_complete = 0;
sub child_init {
    $init_complete = 1;

    OpenSRF::System->bootstrap_client(config_file => $bs_config);
    return Apache2::Const::OK;
}

sub _create_new_editor {
    my $cgi = shift;
    my $auth = $cgi->param('ses') ||
        $cgi->cookie('eg.auth.token') || $cgi->cookie('ses');
    $auth =~ s/"//g;

    return new_editor(authtoken => $auth);
}


sub handler {
    child_init unless $init_complete;

    my $r = shift;
    my $cgi = shift || CGI::new;
    my $editor = shift || _create_new_editor($cgi);
    my $cache = shift || OpenILS::WWW::PrintTemplate::TemplateCache->new;

    $r->content_type('text/plain');

    unless ($editor->checkauth && $editor->allowed('ADMIN_PRINT_TEMPLATE')) {
        $r->print('FORBIDDEN');
        return Apache2::Const::FORBIDDEN;
    }

    my $org_unit_id = $cgi->param('template_owner');
    unless ($org_unit_id) {
        $r->print('Missing template_owner param');
        return Apache2::Const::HTTP_BAD_REQUEST;
    }

    if ($cache->clear_templates($org_unit_id)) {
        $r->print('OK');
        return Apache2::Const::OK;
    } else {
        $r->print("Could not clear cache for org unit $org_unit_id");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

}

1;
