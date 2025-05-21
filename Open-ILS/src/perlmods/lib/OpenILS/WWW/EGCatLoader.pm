package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use XML::LibXML;
use URI::Escape;
use Digest::MD5 qw(md5_hex);
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Cache;
use OpenILS::Event;
use DateTime::Format::ISO8601;
use CGI qw(:all -utf8);
use Time::HiRes;

# EGCatLoader sub-modules 
use OpenILS::WWW::EGCatLoader::Util;
use OpenILS::WWW::EGCatLoader::Account;
use OpenILS::WWW::EGCatLoader::Browse;
use OpenILS::WWW::EGCatLoader::Library;
use OpenILS::WWW::EGCatLoader::Search;
use OpenILS::WWW::EGCatLoader::Record;
use OpenILS::WWW::EGCatLoader::Course;
use OpenILS::WWW::EGCatLoader::Container;
use OpenILS::WWW::EGCatLoader::SMS;
use OpenILS::WWW::EGCatLoader::Register;
use OpenILS::WWW::EGCatLoader::OpenAthens;
use OpenILS::WWW::EGCatLoader::Ecard;

my $U = 'OpenILS::Application::AppUtils';

use constant COOKIE_STAFF_TOKEN => 'eg.auth.token';
use constant COOKIE_STAFF_TIMEOUT => 'eg.auth.time';

use constant COOKIE_SES => 'ses';
use constant COOKIE_LOGGEDIN => 'eg_loggedin';
use constant COOKIE_SHIB_LOGGEDOUT => 'eg_shib_logged_out';
use constant COOKIE_SHIB_LOGGEDIN => 'eg_shib_logged_in';
use constant COOKIE_TZ => 'client_tz';
use constant COOKIE_PHYSICAL_LOC => 'eg_physical_loc';
use constant COOKIE_SSS_EXPAND => 'eg_sss_expand';

use constant COOKIE_ANON_CACHE => 'anoncache';
use constant COOKIE_CART_CACHE => 'cartcache';
use constant CART_CACHE_MYLIST => 'mylist';
use constant ANON_CACHE_STAFF_SEARCH => 'staffsearch';

use constant DEBUG_TIMING => 0;

sub new {
    my($class, $apache, $ctx) = @_;

    my $self = bless({}, ref($class) || $class);

    $self->apache($apache);
    $self->ctx($ctx);
    $self->cgi(new CGI);
    $self->timelog("New page");

    # Add a timelog helper to the context
    $self->ctx->{timelog} = sub { return $self->timelog(@_) };

    OpenILS::Utils::CStoreEditor->init; # just in case
    $self->editor(new_editor());

    return $self;
}

sub DESTROY {
    my $self = shift;
    $ENV{TZ} = $self->ctx->{original_tz}
        if ($self->ctx && exists $self->ctx->{original_tz});
}

# current Apache2::RequestRec;
sub apache {
    my($self, $apache) = @_;
    $self->{apache} = $apache if $apache;
    return $self->{apache};
}

# runtime / template context
sub ctx {
    my($self, $ctx) = @_;
    $self->{ctx} = $ctx if $ctx;
    return $self->{ctx};
}

# cstore editor
sub editor {
    my($self, $editor) = @_;
    $self->{editor} = $editor if $editor;
    return $self->{editor};
}

# CGI handle
sub cgi {
    my($self, $cgi) = @_;
    $self->{cgi} = $cgi if $cgi;
    return $self->{cgi};
}

sub timelog {
    my($self, $description) = @_;

    return unless DEBUG_TIMING;
    return unless $description;
    $self->ctx->{timing} ||= [];
    
    my $timer = [Time::HiRes::gettimeofday()];
    $self->ctx->{time_begin} ||= $timer;

    push @{$self->ctx->{timing}}, [
        Time::HiRes::tv_interval($self->ctx->{time_begin}, $timer), $description
    ];
}

# -----------------------------------------------------------------------------
# Perform initial setup, load common data, then load page data
# -----------------------------------------------------------------------------
sub load {
    my $self = shift;

    $self->init_ro_object_cache;
    $self->timelog("Initial load");

    my $stat = $self->load_common;
    return $stat unless $stat == Apache2::Const::OK;

    my $path = $self->apache->path_info;

    if ($path =~ m|opac/?$|) {
        # nowhere specified, just go home
        return $self->generic_redirect($self->ctx->{home_page});
    }

    (undef, $self->ctx->{mylist}) = $self->fetch_mylist unless
        $path =~ /opac\/my(opac\/lists|list)/ ||
        $path =~ m!opac/api/mylist!;

    my $org_unit = $self->ctx->{physical_loc} || $self->cgi->param('context_org') || $self->_get_search_lib;
    $self->ctx->{selected_print_email_loc} = $org_unit;

    return $self->load_api_mylist_retrieve if $path =~ m|opac/api/mylist/retrieve|;
    return $self->load_api_mylist_add if $path =~ m|opac/api/mylist/add|;
    return $self->load_api_mylist_delete if $path =~ m|opac/api/mylist/delete|;
    return $self->load_api_mylist_clear if $path =~ m|opac/api/mylist/clear|;

    return $self->load_simple("home") if $path =~ m|opac/home|;
    return $self->load_simple("css") if $path =~ m|opac/css|;
    return $self->load_cresults if $path =~ m|opac/course/results|;
    return $self->load_simple("course_search") if $path =~ m|opac/course_search|;
    return $self->load_simple("advanced") if
        $path =~ m:opac/(advanced|numeric|expert):;

    return $self->load_library if $path =~ m|opac/library|;
    return $self->load_rresults if $path =~ m|opac/results|;
    return $self->load_print_or_email_preview('print') if $path =~ m|opac/record/print_preview|;
    return $self->load_print_record if $path =~ m|opac/record/print|;
    return $self->load_record if $path =~ m|opac/record/\d|;
    return $self->load_cnbrowse if $path =~ m|opac/cnbrowse|;
    return $self->load_browse if $path =~ m|opac/browse|;
    return $self->load_course_browse if $path =~ m|opac/course_browse|;
    return $self->load_course if $path =~ m|opac/course|;

    return $self->load_mylist_add if $path =~ m|opac/mylist/add|;
    return $self->load_mylist_delete if $path =~ m|opac/mylist/delete|;
    return $self->load_mylist_move if $path =~ m|opac/mylist/move|;
    return $self->load_mylist_print if $path =~ m|opac/mylist/doprint|;
    return $self->load_mylist if $path =~ m|opac/mylist| && $path !~ m|opac/mylist/email| && $path !~ m|opac/mylist/doemail|;
    return $self->load_cache_clear if $path =~ m|opac/cache/clear|;
    return $self->load_temp_warn_post if $path =~ m|opac/temp_warn/post|;
    return $self->load_temp_warn if $path =~ m|opac/temp_warn|;
    return $self->load_simple("carousel") if $path =~ m|opac/carousel|;

    # ----------------------------------------------------------------
    #  Everything below here requires SSL
    # ----------------------------------------------------------------
    return $self->redirect_ssl unless $self->cgi->https;
    return $self->load_password_reset if $path =~ m|opac/password_reset|;
    return $self->load_logout if $path =~ m|opac/logout|;
    return $self->load_patron_reg if $path =~ m|opac/register|;
    return $self->load_openathens_logout if $path =~ m|opac/sso/openathens/logout$|;

    $self->load_simple("myopac") if $path =~ m:opac/myopac:; # A default page for myopac parts

    $self->_set_ecard_context(); # need to set enough of the context to
                                 # determine on account preferences
                                 # and the account home page whether to offer e-renewal
    return $self->load_ecard_form if $path =~ m|opac/ecard/form|;
    # PINES - online account registration
    return $self->load_ecard_submit if $path =~ m|opac/ecard/submit|;

    # PINES - online account renewal
    return $self->load_ecard_renew if $path =~ m|opac/ecard/renew|;

    if($path =~ m|opac/login|) {
        return $self->load_login unless $self->editor->requestor; # already logged in?

        # This will be less confusing to users than to be shown a login form
        # when they're already logged in.
        return $self->generic_redirect(
            sprintf(
                "%s://%s%s/myopac/main",
                $self->ctx->{proto},
                $self->ctx->{hostname}, $self->ctx->{opac_root}
            )
        );
    }

    if ($path =~ m|opac/sms_cn| and !$self->editor->requestor) {
        my $skip_sms_auth = $self->ctx->{get_org_setting}->($org_unit, 'sms.disable_authentication_requirement.callnumbers');
        return $self->load_sms_cn if $skip_sms_auth;
    }

    if (!$self->editor->requestor && $path =~ m|opac/record/email|) {
        if ($self->ctx->{get_org_setting}->($org_unit, 'opac.email_record.allow_without_login')) {
            my $cache = OpenSRF::Utils::Cache->new('global');

            if ($path !~ m|preview|) { # the real thing!
                $logger->info("not preview");
                my $cap_key = $self->ctx->{cap}->{key} = $self->cgi->param('capkey');
                $logger->info("got cap_key $cap_key");
                if ($cap_key) {
                    my $cap_answer = $self->ctx->{cap_answer} = $self->cgi->param('capanswer');
                    my $real_answer = $self->ctx->{real_answer} = $cache->get_cache(md5_hex($cap_key));
                    $logger->info("got answers $cap_answer $real_answer");
                    return $self->load_email_record(1) if ( $cap_answer eq $real_answer );
                }
            }

            my $captcha = {};
            $$captcha{key} = time() . $$ . rand();
            $$captcha{left} = int(rand(10));
            $$captcha{right} = int(rand(10));
            $cache->put_cache(md5_hex($$captcha{key}), $$captcha{left} + $$captcha{right});
            $self->ctx->{captcha} = $captcha;
            return $self->load_print_or_email_preview('email', 1) if $path =~ m|opac/record/email_preview|;
        }
    }

    return $self->load_manual_shib_login if $path =~ m|opac/manual_shib_login|;
    return $self->load_staff_sso_login if $path =~ m|staff/sso/login$|;
    return $self->load_staff_sso_logout if $path =~ m|staff/sso/logout$|;

    # ----------------------------------------------------------------
    #  Everything below here requires authentication
    # ----------------------------------------------------------------
    return $self->redirect_auth unless $self->editor->requestor;

    # Don't cache anything requiring auth for security reasons
    $self->apache->headers_out->add("cache-control" => "no-store, no-cache, must-revalidate");
    $self->apache->headers_out->add("expires" => "-1");

    if ($path =~ m|opac/mylist/email|) {
        (undef, $self->ctx->{mylist}) = $self->fetch_mylist;
    }
    $self->load_simple("mylist/email") if $path =~ m|opac/mylist/email|;
    return $self->load_print_or_email_preview('email') if $path =~ m|opac/mylist/doemail_preview|;
    return $self->load_mylist_email if $path =~ m|opac/mylist/doemail|;
    return $self->load_print_or_email_preview('email') if $path =~ m|opac/record/email_preview|;
    return $self->load_email_record if $path =~ m|opac/record/email|;
    return $self->load_sms_cn if $path =~ m|opac/sms_cn|;

    return $self->load_place_hold if $path =~ m|opac/place_hold|;
 
    # centralize check for curbside tab display
    $self->load_current_curbside_libs;

    return $self->load_myopac_holds if $path =~ m|opac/myopac/holds|;
    return $self->load_myopac_hold_subscriptions if $path =~ m|opac/myopac/hold_subscriptions|;
    return $self->load_myopac_circs if $path =~ m|opac/myopac/circs|;
    return $self->load_myopac_messages if $path =~ m|opac/myopac/messages|;
    return $self->load_myopac_payment_form if $path =~ m|opac/myopac/main_payment_form|;
    return $self->load_myopac_payments if $path =~ m|opac/myopac/main_payments|;
    return $self->load_myopac_pay_init if $path =~ m|opac/myopac/main_pay_init|;
    return $self->load_myopac_pay if $path =~ m|opac/myopac/main_pay|;
    return $self->load_myopac_main if $path =~ m|opac/myopac/charges|;
    return $self->load_myopac_main if $path =~ m|opac/myopac/main|;
    return $self->load_myopac_receipt_email if $path =~ m|opac/myopac/receipt_email|;
    return $self->load_myopac_receipt_print if $path =~ m|opac/myopac/receipt_print|;
    return $self->load_myopac_update_email if $path =~ m|opac/myopac/update_email|;
    return $self->load_myopac_update_password if $path =~ m|opac/myopac/update_password|;
    return $self->load_myopac_update_username if $path =~ m|opac/myopac/update_username|;
    return $self->load_myopac_update_locale if $path =~ m|opac/myopac/update_locale|;
    return $self->load_myopac_update_preferred_name if $path =~ m|opac/myopac/update_preferred_name|;
    return $self->load_myopac_bookbags if $path =~ m|opac/myopac/lists|;
    return $self->load_myopac_bookbag_print if $path =~ m|opac/myopac/list/print|;
    return $self->load_myopac_bookbag_update if $path =~ m|opac/myopac/list/update|;
    return $self->load_myopac_circ_history_export if $path =~ m|opac/myopac/circ_history/export|;
    return $self->load_myopac_circ_history if $path =~ m|opac/myopac/circ_history|;
    return $self->load_myopac_hold_history if $path =~ m|opac/myopac/hold_history|;
    return $self->load_myopac_prefs_notify_changed_holds if $path =~ m|opac/myopac/prefs_notify_changed_holds|;
    return $self->load_myopac_prefs_notify if $path =~ m|opac/myopac/prefs_notify|;
    return $self->load_myopac_prefs_settings if $path =~ m|opac/myopac/prefs_settings|;
    return $self->load_myopac_prefs_my_lists if $path =~ m|opac/myopac/prefs_my_lists|;
    return $self->load_myopac_prefs if $path =~ m|opac/myopac/prefs|;
    return $self->load_myopac_reservations if $path =~ m|opac/myopac/reservations|;
    return $self->load_openathens_sso if $path =~ m|opac/sso/openathens$|;

    return Apache2::Const::OK;
}


# -----------------------------------------------------------------------------
# Redirect to SSL equivalent of a given page
# -----------------------------------------------------------------------------
sub redirect_ssl {
    my $self = shift;
    my $new_page = sprintf('%s://%s%s', ($self->ctx->{is_staff} ? 'oils' : 'https'), $self->ctx->{hostname}, $self->apache->unparsed_uri);
    return $self->generic_redirect($new_page);
}

# -----------------------------------------------------------------------------
# If an authnticated resource is requested w/o auth, redirect to the login page,
# then return to the originally requrested resource upon successful login.
# -----------------------------------------------------------------------------
sub redirect_auth {
    my $self = shift;

    my $sso_org = $self->ctx->{sso_org};
    my $sso_enabled = $self->ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.enable');
    my $sso_native = $self->ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.allow_native');

    my $login_type = ($sso_enabled and !$sso_native) ? 'manual_shib_login' : 'login';
    my $login_page = sprintf('%s://%s%s/%s',($self->ctx->{is_staff} ? 'oils' : 'https'), $self->ctx->{hostname}, $self->ctx->{opac_root}, $login_type);
    my $redirect_to = uri_escape_utf8($self->apache->unparsed_uri);
    my $redirect_url = "$login_page?redirect_to=$redirect_to";

    return $self->generic_redirect($redirect_url);
}

# -----------------------------------------------------------------------------
# Fall-through for loading a basic page
# -----------------------------------------------------------------------------
sub load_simple {
    my ($self, $page) = @_;

    $self->ctx->{page} = $page;
    $self->ctx->{search_ou} = $self->_get_search_lib();

    return Apache2::Const::OK;
}

# -----------------------------------------------------------------------------
# Tests to see if the user is authenticated and sets some common context values
# -----------------------------------------------------------------------------
sub load_common {
    my $self = shift;

    my $e = $self->editor;
    my $ctx = $self->ctx;

    # redirect non-https to https if we think we are already logged in
    if ($self->cgi->cookie(COOKIE_LOGGEDIN)) {
        return $self->redirect_ssl unless $self->cgi->https;
    }

    # XXX Cache this? Makes testing difficult as apache needs a restart.
    my $default_sort = $e->retrieve_config_global_flag('opac.default_sort');
    $ctx->{default_sort} =
        ($default_sort && $U->is_true($default_sort->enabled)) ? $default_sort->value : '';

    $ctx->{client_tz} = $self->cgi->cookie(COOKIE_TZ) || $ENV{TZ};
    $ctx->{referer} = $self->cgi->referer;
    $ctx->{path_info} = $self->cgi->path_info;
    $ctx->{full_path} = $ctx->{base_path} . $self->cgi->path_info;
    $ctx->{unparsed_uri} = $self->apache->unparsed_uri;
    $ctx->{opac_root} = $ctx->{base_path} . "/opac"; # absolute base url

    $ctx->{original_tz} = $ENV{TZ};
    $ENV{TZ} = $ctx->{client_tz};

    my $xul_wrapper = 
        ($self->apache->headers_in->get('OILS-Wrapper') || '') =~ /true/;

    if ($xul_wrapper) {
        # XUL client
        $ctx->{is_staff} = 1;
        $ctx->{proto} = 'oils';
        $ctx->{hostname} = 'remote';
    }

    $ctx->{carousel_loc} = $self->get_carousel_loc;
    $ctx->{physical_loc} = $self->get_physical_loc;
    my $geo_sort = $e->retrieve_config_global_flag('opac.use_geolocation');
    $geo_sort = ($geo_sort && $U->is_true($geo_sort->enabled));
    my $geo_org = $ctx->{physical_loc} || $self->cgi->param('loc') || $ctx->{aou_tree}->()->id;
    my $geo_sort_for_org = $ctx->{get_org_setting}->($geo_org, 'opac.holdings_sort_by_geographic_proximity');
    $ctx->{geo_sort} = $geo_sort && $U->is_true($geo_sort_for_org);
    my $part_required_flag = $e->retrieve_config_global_flag('circ.holds.api_require_monographic_part_when_present');
    $part_required_flag = ($part_required_flag and $U->is_true($part_required_flag->enabled));
    $ctx->{part_required_when_present_global_flag} = $part_required_flag;

    # capture some commonly accessed pages
    $ctx->{home_page} = $ctx->{proto} . '://' . $ctx->{hostname} . $self->ctx->{opac_root} . "/home";
    $ctx->{logout_page} = ($ctx->{proto} eq 'http' ? 'https' : $ctx->{proto} ) . '://' . $ctx->{hostname} . $self->ctx->{opac_root} . "/logout";

    if($e->authtoken($self->cgi->cookie(COOKIE_SES))) {

        if($e->checkauth) {

            $ctx->{authtoken} = $e->authtoken;
            $ctx->{authtime} = $e->authtime;
            $ctx->{user} = $e->requestor;
            my $card = $self->editor->retrieve_actor_card($ctx->{user}->card);
            $ctx->{active_card} = (ref $card) ? $card->barcode : undef;
            $ctx->{place_unfillable} = 1 if $e->requestor->wsid && $e->allowed('PLACE_UNFILLABLE_HOLD', $e->requestor->ws_ou);

            # The browser client does not set an OILS-Wrapper header (above).
            # The presence of a workstation and no header indicates staff mode.
            # FIXME: this approach leaves un-wrapped TPAC's within the same
            # browser (and hence same ses cookie) in an unnatural is_staff
            # state.  Consider alternatives for determining is_staff / 
            # is_browser_staff when $xul_wrapper is false.
            if (!$xul_wrapper and $e->requestor->wsid) {
                $ctx->{is_staff} = 1;
                $ctx->{is_browser_staff} = 1;
            }

            $self->update_dashboard_stats();

        } else {

            # if we encounter a stale authtoken, call load_logout 
            # to clean up the cookie, then redirect the user to the
            # originally requested page
            return $self->load_logout($self->apache->unparsed_uri);
        }
    }

    # List of <meta> and <link> elements to populate
    $ctx->{metalinks} = [];

    $self->extract_copy_location_group_info;
    $ctx->{search_ou} = $self->_get_search_lib();
    if (!$ctx->{search_scope}) { # didn't get it from locg above in extract_...
        $ctx->{search_scope} = $self->cgi->param('search_scope');
        if ($ctx->{search_scope} =~ /^lasso\(([^)]+)\)/) {
            $ctx->{search_lasso} = $1; # make it visible to basic search
        }
    }
    $self->staff_saved_searches_set_expansion_state if $ctx->{is_staff};
    $self->load_eg_cache_hash;
    $self->load_copy_location_groups;
    $self->load_my_hold_subscriptions;
    $self->load_hold_subscriptions if $ctx->{is_staff};
    $self->load_lassos;
    $self->staff_saved_searches_set_expansion_state if $ctx->{is_staff};
    $self->load_search_filter_groups($ctx->{search_ou});
    $self->load_org_util_funcs;
    $self->load_perm_funcs;

    $ctx->{get_visible_carousels} = sub {
        my $org_unit = $self->ctx->{carousel_loc} || $self->ctx->{physical_loc} || $self->cgi->param('loc') || $self->ctx->{aou_tree}->()->id;
        return $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.carousel.retrieve_by_org',
            $org_unit
        );
    };
    $ctx->{get_carousel} = sub {
        my $id = shift;
        return $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.carousel.get_contents',
            $id
        );
    };

    $ctx->{fetch_display_fields} = sub {
        my $id = shift;

        if (@$id == 1) {
            return $ctx->{_hl_data}{''.$$id[0]}
                if ($ctx->{_hl_data}{''.$$id[0]});
        }

        $self->timelog("HL data not cached, fetching from server.");

        my $rows = $U->simplereq(
            'open-ils.search', 
            'open-ils.search.fetch.metabib.display_field.highlight',
            $ctx->{query_struct}{additional_data}{highlight_map},
            map {int($_)} @$id
        );

        $ctx->{_hl_data}{''.$$id[0]} = $rows if (@$id == 1);

        return $rows;
    };

    $ctx->{course_ou} = $ctx->{physical_loc} || $ctx->{aou_tree}->()->id;
    $ctx->{use_courses} = $ctx->{get_org_setting}->($ctx->{course_ou}, 'circ.course_materials_opt_in') ? 1 : 0;

    $ctx->{sso_org} = $ENV{sso_loc} || $ctx->{physical_loc} || $ctx->{search_ou};

    return Apache2::Const::OK;
}

sub update_dashboard_stats {
    my $self = shift;

    my $e = $self->editor;
    my $ctx = $self->ctx;

    $ctx->{user_stats} = $U->simplereq(
        'open-ils.actor', 
        'open-ils.actor.user.opac.vital_stats', 
        $e->authtoken, $e->requestor->id);
}

sub staff_saved_searches_set_expansion_state {
    my $self = shift;

    my $param = $self->cgi->param('sss_expand');
    my $value;
    
    if (defined $param) {
        $value = ($param ? 1 : 0);
        $self->apache->headers_out->add(
            "Set-Cookie" => $self->cgi->cookie(
                -name => COOKIE_SSS_EXPAND,
                -path => $self->ctx->{base_path},
                -secure => 1,   # not strictly necessary, but this feature is staff-only, so may as well
                -value => $value,
                -expires => undef
            )
        );
    } else {
        $value = $self->cgi->cookie(COOKIE_SSS_EXPAND);
    }

    $self->ctx->{saved_searches_expanded} = $value;
}

# physical_loc (i.e. "original location") passed in as a URL 
# param will replace any existing physical_loc stored as a cookie.
# If specified via ENV that rules over all and we don't set cookies.
sub get_physical_loc {
    my $self = shift;

    return $ENV{physical_loc} if($ENV{physical_loc});

    if(my $physical_loc = $self->cgi->param('physical_loc')) {
        $self->apache->headers_out->add(
            "Set-Cookie" => $self->cgi->cookie(
                -name => COOKIE_PHYSICAL_LOC,
                -path => $self->ctx->{base_path},
                -value => $physical_loc,
                -expires => undef
            )
        );
        return $physical_loc;
    }

    return $self->cgi->cookie(COOKIE_PHYSICAL_LOC);
}

sub get_carousel_loc {
    my $self = shift;
    return $self->cgi->param('carousel_loc') || $ENV{carousel_loc};
}

sub load_staff_sso_logout {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;

    my $redirect_to = shift || $cgi->param('redirect_to') || '/eg2/staff/login';
    my $cookie_list = [];

    my $ws_org;
    if (my $staff_session = $self->cgi->cookie(COOKIE_STAFF_TOKEN)) {
        $staff_session =~ s/^"//;
        $staff_session =~ s/"$//;
        if($self->editor->authtoken($staff_session) and $self->editor->checkauth) {
            $ws_org = $self->editor->requestor->ws_ou;
        }
    }

    my $sso_org = $ws_org || $ctx->{sso_org};
    if ($sso_org and $ctx->{get_org_setting}->($sso_org, 'staff.login.shib_sso.enable')) { # we're allowed to attempt SSO

        my $active_logout = $cgi->param('active_logout');

        my $sso_entity_id = $ctx->{get_org_setting}->($sso_org, 'staff.login.shib_sso.entityId');
        my $sso_logout = $ctx->{get_org_setting}->($sso_org, 'staff.login.shib_sso.logout');

        # If using SSO, and actively logging out of EG /or/ staff.login.shib_sso.logout is true then
        # log out of the SP (and, depending on Shib config, maybe the IdP or globally).
        if ($sso_logout or $active_logout) {
            my $shib_app_path = $ctx->{get_org_setting}->($sso_org, 'staff.login.shib_sso.shib_path') || '/Shibboleth.sso';
            $redirect_to = $shib_app_path . '/Logout?return=' . uri_escape_utf8($redirect_to);
            undef $shib_app_path;
            if ($sso_entity_id) {
                $redirect_to .= '&entityID=' . $sso_entity_id;
            }
        }

        # clear value of and expire both of these login-related cookies
        $cookie_list = [
            $cgi->cookie(
                -name => COOKIE_SHIB_LOGGEDIN,
                -path => '/',
                -value => '0',
                -expires => '-1h'
            ),
            $cgi->cookie(
                -name => COOKIE_STAFF_TOKEN, # staff auth token cookie
                -path => '/',
                -secure => 1,
                -value => '',
                -expires => '-1h'
            ),
            $cgi->cookie(
                -name => COOKIE_STAFF_TIMEOUT,
                -path => '/',
                -secure => 1,
                -value => '',
                -expires => '-1h'
            ),
            $cgi->cookie(
                -name => COOKIE_SES, # opac auth token cookie
                -path => '/',
                -value => '',
                -expires => '-1h'
            ),
            $cgi->cookie(
                -name => COOKIE_LOGGEDIN,
                -path => '/',
                -value => '',
                -expires => '-1h'
            )
        ];

        if ($active_logout) {
            push @$cookie_list,$cgi->cookie(
                -name => COOKIE_SHIB_LOGGEDOUT,
                -path => '/',
                -value => '1',
                -expires => '2147483647'
            );
        }
    }

    # If the user was adding anything to an anonymous cache 
    # while logged in, go ahead and clear it out.
    $self->clear_anon_cache;

    try { # a missing auth token will cause an ugly explosion
        $U->simplereq(
            'open-ils.auth',
            'open-ils.auth.session.delete',
            $cgi->cookie(COOKIE_STAFF_TOKEN)
        );
    } catch Error with {};

    return $self->generic_redirect($redirect_to, $cookie_list);
}

sub load_staff_sso_login {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;

    my $here = $cgi->url( -path => 1 );
    my $ws_name = $cgi->param('ws');
    my $redirect_to = $cgi->param('redirect_to') || ''; 

    my $url = '/eg2/staff/login'; # when in doubt, head to the front door
    my $cookie_list = [];

    my $ws_org;
    if ($ws_name) {
        if (my $ws = $self->editor->search_actor_workstation({name => $ws_name})->[0]) {
            $ws_org = $ws->owning_lib;
        }
    }

    my $sso_org = $ws_org || $ctx->{sso_org};
    if ($sso_org and $ctx->{get_org_setting}->($sso_org, 'staff.login.shib_sso.enable')) { # we're allowed to attempt SSO

        my $sso_shib_match = $ctx->{get_org_setting}->($sso_org, 'staff.login.shib_sso.shib_matchpoint') || 'uid';
        $logger->info("Looking for SSO matchpoint attribute: $sso_shib_match");

        my $sso_user_match_value = $ENV{$sso_shib_match};
        $logger->info("SSO matchpoint $sso_shib_match contains: $sso_user_match_value");

        if ($sso_user_match_value) { # We already have a Shibboleth matchpoint value, complete the login dance

            my $sso_eg_match = $ctx->{get_org_setting}->($sso_org, 'staff.login.shib_sso.evergreen_matchpoint') || 'usrname';
            $logger->info("Have an SSO user match value: $sso_user_match_value");
            $self->timelog("Have an SSO user match value: $sso_user_match_value");

            if ($sso_eg_match eq 'barcode') { # barcode is special
                my $card = $self->editor->search_actor_card({barcode => $sso_user_match_value})->[0];
                $sso_user_match_value = $card ? $card->usr : undef;
                $sso_eg_match = 'id';
            }

            if ($sso_user_match_value && $sso_eg_match) {
                my $user = $self->editor->search_actor_user({ $sso_eg_match => $sso_user_match_value })->[0];
                if ($user) { # create a session

                    # should we start provisional?
                    my $attempt_mfa = $U->simplereq('open-ils.auth_mfa', 'open-ils.auth_mfa.enabled');

                    my $session = $U->simplereq(
                        'open-ils.auth_internal',
                        'open-ils.auth_internal.session.create',
                        { user_id     => $user->id,
                          workstation => $ws_name,
                          login_type  => 'staff',
                          provisional => 0+$attempt_mfa # MUST be actually numeric
                        }
                    )->{payload};

                    $redirect_to = undef if $redirect_to =~ m#eg2?(?:/\w{2}-\w{2})?/staff/login#; # the login page logs you out, and we don't want that
                    $url = $redirect_to || '/eg2/staff/splash';

                    # both login-related cookies should expire at the same time
                    my $login_cookie_expires = CORE::time + $session->{authtime};

                    my $cookie_suffix = $session->{provisional} ? '.provisional' : '';
                    $cookie_list = [
                        $cgi->cookie(
                            -name => COOKIE_STAFF_TOKEN . $cookie_suffix,
                            -path => '/',
                            -secure => 1,
                            -value => '"'.$session->{authtoken}.'"',
                            -expires => $login_cookie_expires
                        ),
                        $cgi->cookie(
                            -name => COOKIE_STAFF_TIMEOUT . $cookie_suffix,
                            -path => '/',
                            -secure => 1,
                            -value => $session->{authtime},
                            -expires => $login_cookie_expires
                        ),
                        $cgi->cookie(
                            -name => COOKIE_SHIB_LOGGEDOUT,
                            -path => '/',
                            -value => '0',
                            -expires => '-1h'
                        )
                    ];

                }
            }

        } else { # We need to ask Shib to give us a session
            my $shib_app_path = $ctx->{get_org_setting}->($sso_org, 'staff.login.shib_sso.shib_path') || '/Shibboleth.sso';

            $url = $shib_app_path . '/Login?target=' . uri_escape_utf8($here.'?ws='.$ws_name.'&redirect_to='.uri_escape_utf8($redirect_to));

            undef $shib_app_path;

            my $sso_entity_id = $ctx->{get_org_setting}->($sso_org, 'staff.login.shib_sso.entityId');
            if ($sso_entity_id) {
                $url .= '&entityID=' . $sso_entity_id;
            }

            $cookie_list =  [
                $self->cgi->cookie(
                    -name => COOKIE_SHIB_LOGGEDOUT,
                    -path => '/',
                    -value => '0',
                    -expires => '-1h'
                )
            ];
        }
    }

    return $self->generic_redirect( $url, $cookie_list );
}

# -----------------------------------------------------------------------------
# Log in and redirect to the redirect_to URL (or home)
# -----------------------------------------------------------------------------
sub load_login {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;

    $self->timelog("Load login begins");

    my $sso_org = $ctx->{sso_org};

    my $sso_enabled = $ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.enable');
    my $sso_native = $ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.allow_native');
    my $sso_eg_match = $ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.evergreen_matchpoint') || 'usrname';
    my $sso_shib_match = $ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.shib_matchpoint') || 'uid';

    $ctx->{page} = 'login';

    my $username = $cgi->param('username') || '';
    $username =~ s/\s//g;  # Remove blanks
    my $password = $cgi->param('password');
    my $org_unit = $ctx->{physical_loc} || $ctx->{aou_tree}->()->id;
    my $persist = $cgi->param('persist');
    my $client_tz = $cgi->param('client_tz');

    my $sso_user_match_value = $ENV{$sso_shib_match};
    my $response;
    my $sso_logged_in;
    $self->timelog("SSO is enabled") if ($sso_enabled);
    if ($sso_enabled
        and $sso_user_match_value
        and (!$self->cgi->cookie(COOKIE_SHIB_LOGGEDOUT) or $self->{_ignore_shib_logged_out_cookie})
    ) { # we have a shib session, and have not cleared a previous shib-login cookie
        $self->{_ignore_shib_logged_out_cookie} = 0; # only set by an intermediate call that internally redirected here
        $self->timelog("Have an SSO user match value: $sso_user_match_value");

        if ($sso_eg_match eq 'barcode') { # barcode is special
            my $card = $self->editor->search_actor_card({barcode => $sso_user_match_value})->[0];
            $sso_user_match_value = $card ? $card->usr : undef;
            $sso_eg_match = 'id';
        }

        if ($sso_user_match_value && $sso_eg_match) {
            my $user = $self->editor->search_actor_user({ $sso_eg_match => $sso_user_match_value })->[0];
            if ($user) { # create a session
                $response = $U->simplereq(
                    'open-ils.auth_internal',
                    'open-ils.auth_internal.session.create',
                    { user_id => $user->id, login_type => 'opac' }
                );
                $sso_logged_in = $response ? 1 : 0;
            }
        }

        $self->timelog("Checked for SSO login");
    }

    if (!$sso_enabled || (!$response && $sso_native)) {
        # initial log form only
        return Apache2::Const::OK unless $username and $password;

        my $auth_proxy_enabled = 0; # default false
        try { # if the service is not running, just let this fail silently
            $auth_proxy_enabled = $U->simplereq(
                'open-ils.auth_proxy',
                'open-ils.auth_proxy.enabled');
        } catch Error with {};

        $self->timelog("Checked for auth proxy: $auth_proxy_enabled; org = $org_unit; username = $username");

        my $args = {
            type => ($persist) ? 'persist' : 'opac',
            org => $org_unit,
            agent => 'opac'
        };

        my $bc_regex = $ctx->{get_org_setting}->($org_unit, 'opac.barcode_regex');

        # To avoid surprises, default to "Barcodes start with digits"
        $bc_regex = '^\d' unless $bc_regex;

        if ($bc_regex and ($username =~ /$bc_regex/)) {
            $args->{barcode} = $username;
        } else {
            $args->{username} = $username;
        }

        if (!$auth_proxy_enabled) {
            my $seed = $U->simplereq(
                'open-ils.auth',
                'open-ils.auth.authenticate.init', $username);
            $args->{password} = md5_hex($seed . md5_hex($password));
            $response = $U->simplereq(
                'open-ils.auth', 'open-ils.auth.authenticate.complete', $args);
        } else {
            $args->{password} = $password;
            $response = $U->simplereq(
                'open-ils.auth_proxy',
                'open-ils.auth_proxy.login', $args);
        }
        $self->timelog("Checked password");
    } else {
        $response ||= OpenILS::Event->new( 'LOGIN_FAILED' ); # assume failure
    }

    if($U->event_code($response)) { 
        # login failed, report the reason to the template
        $ctx->{login_failed_event} = $response;
        return Apache2::Const::OK;
    }

    # login succeeded, redirect as necessary

    my $acct = $self->apache->unparsed_uri;
    $acct =~ s|/login|/myopac/main|;

    # both login-related cookies should expire at the same time
    my $login_cookie_expires = ($persist) ? CORE::time + $response->{payload}->{authtime} : undef;

    my $cookie_list = [
        # contains the actual auth token and should be sent only over https
        $cgi->cookie(
            -name => COOKIE_SES,
            -path => '/',
            -secure => 1,
            -value => $response->{payload}->{authtoken},
            -expires => $login_cookie_expires
        ),
        # contains only a hint that we are logged in, and is used to
        # trigger a redirect to https
        $cgi->cookie(
            -name => COOKIE_LOGGEDIN,
            -path => '/',
            -secure => 0,
            -value => '1',
            -expires => $login_cookie_expires
        )
    ];

    if ($client_tz) {
        # contains the client's tz, as passed by the client
        # trigger a redirect to https
        push @$cookie_list, $cgi->cookie(
            -name => COOKIE_TZ,
            -path => '/',
            -secure => 0,
            -value => $client_tz,
            -expires => $login_cookie_expires
        );
    }

    if ($sso_logged_in) {
        # tells us if we're logged in via shib, so we can decide whether to try logging in again.
        push @$cookie_list, $cgi->cookie(
            -name => COOKIE_SHIB_LOGGEDOUT,
            -path => '/',
            -secure => 0,
            -value => '0',
            -expires => '-1h'
        );
        push @$cookie_list, $cgi->cookie(
            -name => COOKIE_SHIB_LOGGEDIN,
            -path => '/',
            -secure => 0,
            -value => '1',
            -expires => $login_cookie_expires
        );
    }

    # TODO: maybe move this logic to generic_redirect()?
    my $redirect_to = $cgi->param('redirect_to') || $acct;
    if (my $login_redirect_gf = $self->editor->retrieve_config_global_flag('opac.login_redirect_domains')) {
        if ($login_redirect_gf->enabled eq 't') {

            my @redir_hosts = ();
            if ($login_redirect_gf->value) {
                @redir_hosts = map { '(?:[^/.]+\.)*' . quotemeta($_) } grep { $_ } split(/,\s*/, $login_redirect_gf->value);
            }
            unshift @redir_hosts, quotemeta($ctx->{hostname});

            my $hn = join('|', @redir_hosts);
            my $relative_redir = qr#^(?:(?:(?:(?:f|ht)tps?:)?(?://(?:$hn))(?:/|$))|/$|/[^/]+)#;

            if ($redirect_to !~ $relative_redir) {
                $logger->warn(
                    "Login redirection of [$redirect_to] ".
                    "disallowed based on Global Flag opac.".
                    "login_redirect_domains RE [$relative_redir]"
                );
                $redirect_to = $acct; # fall back to myopac/main
            }
        }
    }

    return
        $self->_perform_any_sso_required($response, $redirect_to, $cookie_list)
        || $self->generic_redirect(
            $redirect_to,
            $cookie_list
        );
}

sub load_manual_shib_login {
    my $self = shift;
    my $redirect_to = shift || $self->cgi->param('redirect_to');

    my $sso_org = $self->ctx->{sso_org};
    my $sso_entity_id = $self->ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.entityId');
    my $sso_shib_match = $self->ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.shib_matchpoint') || 'uid';


    if ($ENV{$sso_shib_match}) {
        $self->{_ignore_shib_logged_out_cookie} = 1;
        return $self->load_login;
    }

    my $url = '/Shibboleth.sso/Login?target=' . ($redirect_to || $self->ctx->{home_page});
    if ($sso_entity_id) {
        $url .= '&entityID=' . $sso_entity_id;
    }

    return $self->generic_redirect( $url,
        [
            $self->cgi->cookie(
                -name => COOKIE_SHIB_LOGGEDOUT,
                -path => '/',
                -value => '0',
                -expires => '-1h'
            )
        ]
    );
}

# -----------------------------------------------------------------------------
# Log out and redirect to the home page
# -----------------------------------------------------------------------------
sub load_logout {
    my $self = shift;
    my $redirect_to = shift || $self->cgi->param('redirect_to')
        || $self->ctx->{home_page};
    my $active_logout = $self->cgi->param('active_logout');

    my $sso_org = $self->ctx->{sso_org};

    my $sso_enabled = $self->ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.enable');
    my $sso_entity_id = $self->ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.entityId');
    my $sso_logout = $self->ctx->{get_org_setting}->($sso_org, 'opac.login.shib_sso.logout');

    # If using SSO, and actively logging out of EG /or/ opac.login.shib_sso.logout is true then
    # log out of the SP (and, depending on Shib config, maybe the IdP or globally).
    if ($sso_enabled and ($sso_logout or $active_logout)) {
        $redirect_to = '/Shibboleth.sso/Logout?return=' . ($redirect_to || $self->ctx->{home_page});
        if ($sso_entity_id) {
            $redirect_to .= '&entityID=' . $sso_entity_id;
        }
    }

    # If the user was adding anyting to an anonymous cache 
    # while logged in, go ahead and clear it out.
    $self->clear_anon_cache;

    try { # a missing auth token will cause an ugly explosion
        $U->simplereq(
            'open-ils.auth',
            'open-ils.auth.session.delete',
            $self->cgi->cookie(COOKIE_SES)
        );
    } catch Error with {};

    # clear value of and expire both of these login-related cookies
    my $cookie_list = [
        $self->cgi->cookie(
            -name => COOKIE_SES,
            -path => '/',
            -value => '',
            -expires => '-1h'
        ),
        $self->cgi->cookie(
            -name => COOKIE_LOGGEDIN,
            -path => '/',
            -value => '',
            -expires => '-1h'
        ),
        ($active_logout ? ($self->cgi->cookie(
            -name => COOKIE_SHIB_LOGGEDOUT,
            -path => '/',
            -value => '1',
            -expires => '2147483647'
        )) : ()),
        $self->cgi->cookie(
            -name => COOKIE_SHIB_LOGGEDIN,
            -path => '/',
            -value => '0',
            -expires => '-1h'
        )
    ];

    if ($self->ctx->{is_staff}) {
        push @$cookie_list, 
            $self->cgi->cookie(
                -name => COOKIE_STAFF_TOKEN,
                -path => '/',
                -secure => 1,
                -value => '',
                -expires => '-1h'
            ),
            $self->cgi->cookie(
                -name => COOKIE_STAFF_TIMEOUT,
                -path => '/',
                -secure => 1,
                -value => '',
                -expires => '-1h'
            );
    }

    return 
        $self->_perform_any_sso_signout_required($redirect_to, $cookie_list)
        || $self->generic_redirect(
            $redirect_to,
            $cookie_list
        );
}

# -----------------------------------------------------------------------------
# Signs the user in to any third party services that their org unit is
# configured for.
# -----------------------------------------------------------------------------
sub _perform_any_sso_required {
    my ($self, $auth_response, $redirect_to, $cookie_list) = @_;

    return $self->perform_openathens_sso_if_required(
        $auth_response,
        $redirect_to,
        $cookie_list
    );
}

# -----------------------------------------------------------------------------
# Signs the user out of any third party services that their org unit is
# configured for.
# -----------------------------------------------------------------------------
sub _perform_any_sso_signout_required {
    my ($self, $redirect_to, $cookie_list) = @_;

    return $self->perform_openathens_signout_if_required(
        $redirect_to,
        $cookie_list
    );
}

1;

