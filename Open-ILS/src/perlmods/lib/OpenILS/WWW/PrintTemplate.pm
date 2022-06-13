package OpenILS::WWW::PrintTemplate;
use strict; use warnings;
use Apache2::Const -compile => 
    qw(OK FORBIDDEN NOT_FOUND HTTP_INTERNAL_SERVER_ERROR HTTP_BAD_REQUEST);
use Apache2::RequestRec;
use CGI;
use HTML::Defang;
use DateTime;
use DateTime::Format::ISO8601;
use Unicode::Normalize;
use OpenSRF::Utils::JSON;
use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;

my $U = 'OpenILS::Application::AppUtils';
my $helpers;

my $bs_config;
my $enable_cache; # Enable process-level template caching
sub import {
    $bs_config = shift;
    $enable_cache = shift;
}

my $init_complete = 0;
sub child_init {
    $init_complete = 1;

    OpenSRF::System->bootstrap_client(config_file => $bs_config);
    OpenILS::Utils::CStoreEditor->init;
    return Apache2::Const::OK;
}

# HTML scrubber
# https://metacpan.org/pod/HTML::Defang
my $defang = HTML::Defang->new;

sub handler {
    my $r = shift;
    my $cgi = CGI->new;

    child_init() unless $init_complete;

    my $auth = $cgi->param('ses') || 
        $cgi->cookie('eg.auth.token') || $cgi->cookie('ses');

    my $e = new_editor(authtoken => $auth);

    # Requires staff login
    return Apache2::Const::FORBIDDEN 
        unless $e->checkauth && $e->allowed('STAFF_LOGIN');

    # Let pcrud handle the authz
    #$e->{app} = 'open-ils.pcrud';
    $e->personality('open-ils.pcrud');

    my $tmpl_owner = $cgi->param('template_owner') || $e->requestor->ws_ou;
    my $tmpl_locale = $cgi->param('template_locale') || 'en-US';
    my $tmpl_id = $cgi->param('template_id');
    my $tmpl_name = $cgi->param('template_name');
    my $tmpl_data = $cgi->param('template_data');
    my $client_timezone = $cgi->param('client_timezone');

    return Apache2::Const::HTTP_BAD_REQUEST unless $tmpl_name || $tmpl_id;

    my $template = 
        find_template($e, $tmpl_id, $tmpl_name, $tmpl_locale, $tmpl_owner)
        or return Apache2::Const::NOT_FOUND;

    my $data;
    eval { $data = OpenSRF::Utils::JSON->JSON2perl($tmpl_data); };
    if ($@) {
        $logger->error("Invalid JSON in template compilation: $tmpl_data");
        return Apache2::Const::HTTP_BAD_REQUEST;
    }

    my $staff_org = $e->retrieve_actor_org_unit([
        $e->requestor->ws_ou, {
            flesh => 1, 
            flesh_fields => {
                aou => [
                    'billing_address', 
                    'mailing_address', 
                    'hours_of_operation'
                ]
            }
        }
    ]);

    my $output = '';
    my $tt = Template->new;
    my $tmpl = $template->template;

    my $context = {
        template_locale => $tmpl_locale,
        client_timezone => $client_timezone,
        staff => $e->requestor,
        staff_org => $staff_org,
        staff_org_timezone => get_org_timezone($e, $staff_org->id),
        helpers => $helpers,
        template_data => $data
    };

    my $stat = $tt->process(\$tmpl, $context, \$output);

    if ($stat) { # OK
        my $ctype = $template->content_type;
        if ($ctype eq 'text/html') {
            $output = $defang->defang($output); # Scrub the HTML
        }
        # TODO
        # client current expects content type to only contain type.
        # $r->content_type("$ctype; encoding=utf8");
        $r->content_type($ctype);
        $r->print($output);
        return Apache2::Const::OK;

    } else {

        (my $error = $tt->error) =~ s/\n/ /og;
        $logger->error("Error processing print template: $error");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }
}

my %org_timezone_cache;
sub get_org_timezone {
    my ($e, $org_id) = @_;

    if (!$org_timezone_cache{$org_id}) {

        # open-ils.auth call required since our $e is in pcrud mode.
        my $value = $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.ou_setting.ancestor_default', 
            $org_id, 'lib.timezone');

        $org_timezone_cache{$org_id} = $value ? $value->{value} : 
            DateTime->now(time_zone => 'local')->time_zone->name;
    }

    return $org_timezone_cache{$org_id};
}


# Find the template closest to the specific org unit owner.
my %template_cache;
sub find_template {
    my ($e, $template_id, $name, $locale, $owner) = @_;

    if ($template_id) {
        # Requesting by ID, generally used for testing, 
        # always pulls the latest value and ignores the active flag
        return $e->retrieve_config_print_template($template_id);
    }

    return  $template_cache{$owner}{$name}{$locale}
        if  $enable_cache &&
            $template_cache{$owner} && 
            $template_cache{$owner}{$name} &&
            $template_cache{$owner}{$name}{$locale};

    while ($owner) {
        my ($org) = $U->fetch_org_unit($owner); # cached in AppUtils
        
        my $template = $e->search_config_print_template({
            name => $name, 
            locale => $locale, 
            owner => $org->id,
            active => 't'
        })->[0];

        if ($template) {

            if ($enable_cache) {
                $template_cache{$owner} = {} unless $template_cache{$owner};
                $template_cache{$owner}{$name} = {} 
                    unless $template_cache{$owner}{$name};
                $template_cache{$owner}{$name}{$locale} = $template;
            }

            return $template;
        }

        $owner = $org->parent_ou;
    }

    return undef;
}

# Utility / helper functions passed into every template

$helpers = {

    # turns a date w/ optional timezone modifier into something 
    # TT can understand
    format_date => sub {
        my $date = shift;
        my $tz = shift;

        $date = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($date));
        $date->set_time_zone($tz) if $tz;

        return sprintf(
            "%0.2d:%0.2d:%0.2d %0.2d-%0.2d-%0.4d",
            $date->hour,
            $date->minute,
            $date->second,
            $date->day,
            $date->month,
            $date->year
        );
    },

    current_date => sub {
        my $tz = shift || 'local';
        my $date = DateTime->now(time_zone => $tz);
        return $helpers->{format_date}->($date);
    },

    get_org_unit => sub {
        my $org_id = shift;
        return $org_id if ref $org_id;
        return new_editor()->retrieve_actor_org_unit($org_id);
    },

    get_org_setting => sub {
        my($org_id, $setting) = @_;
        return $U->ou_ancestor_setting_value($org_id, $setting);
    },

    # Useful for accessing hash values whose key contains dots (.), 
    # which TT interprets as levels within a nested hash.
    #
    # e.g.  So you don't have to do stuff like this:
    # SET field = 'summary.balance_owed'; xact.$field
    hashval => sub {
        my ($hash, $key) = @_;
        return $hash ? $hash->{$key} : undef;
    }
};




1;
