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
use OpenILS::WWW::EGCatLoader::Container;
use OpenILS::WWW::EGCatLoader::SMS;
use OpenILS::WWW::EGCatLoader::Register;

my $U = 'OpenILS::Application::AppUtils';

use constant COOKIE_SES => 'ses';
use constant COOKIE_LOGGEDIN => 'eg_loggedin';
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

    return $self->load_api_mylist_retrieve if $path =~ m|opac/api/mylist/retrieve|;
    return $self->load_api_mylist_add if $path =~ m|opac/api/mylist/add|;
    return $self->load_api_mylist_delete if $path =~ m|opac/api/mylist/delete|;
    return $self->load_api_mylist_clear if $path =~ m|opac/api/mylist/clear|;

    return $self->load_simple("home") if $path =~ m|opac/home|;
    return $self->load_simple("css") if $path =~ m|opac/css|;
    return $self->load_simple("advanced") if
        $path =~ m:opac/(advanced|numeric|expert):;

    return $self->load_library if $path =~ m|opac/library|;
    return $self->load_rresults if $path =~ m|opac/results|;
    return $self->load_print_record if $path =~ m|opac/record/print|;
    return $self->load_record if $path =~ m|opac/record/\d|;
    return $self->load_cnbrowse if $path =~ m|opac/cnbrowse|;
    return $self->load_browse if $path =~ m|opac/browse|;

    return $self->load_mylist_add if $path =~ m|opac/mylist/add|;
    return $self->load_mylist_delete if $path =~ m|opac/mylist/delete|;
    return $self->load_mylist_move if $path =~ m|opac/mylist/move|;
    return $self->load_mylist_print if $path =~ m|opac/mylist/doprint|;
    return $self->load_mylist if $path =~ m|opac/mylist| && $path !~ m|opac/mylist/email| && $path !~ m|opac/mylist/doemail|;
    return $self->load_cache_clear if $path =~ m|opac/cache/clear|;
    return $self->load_temp_warn_post if $path =~ m|opac/temp_warn/post|;
    return $self->load_temp_warn if $path =~ m|opac/temp_warn|;

    # ----------------------------------------------------------------
    #  Everything below here requires SSL
    # ----------------------------------------------------------------
    return $self->redirect_ssl unless $self->cgi->https;
    return $self->load_password_reset if $path =~ m|opac/password_reset|;
    return $self->load_logout if $path =~ m|opac/logout|;
    return $self->load_patron_reg if $path =~ m|opac/register|;

    $self->load_simple("myopac") if $path =~ m:opac/myopac:; # A default page for myopac parts

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
        my $org_unit = $self->ctx->{physical_loc} || $self->cgi->param('loc') || $self->ctx->{aou_tree}->()->id;
        my $skip_sms_auth = $self->ctx->{get_org_setting}->($org_unit, 'sms.disable_authentication_requirement.callnumbers');
        return $self->load_sms_cn if $skip_sms_auth;
    }

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
    return $self->load_mylist_email if $path =~ m|opac/mylist/doemail|;
    return $self->load_email_record if $path =~ m|opac/record/email|;

    return $self->load_place_hold if $path =~ m|opac/place_hold|;
    return $self->load_myopac_holds if $path =~ m|opac/myopac/holds|;
    return $self->load_myopac_circs if $path =~ m|opac/myopac/circs|;
    return $self->load_myopac_messages if $path =~ m|opac/myopac/messages|;
    return $self->load_myopac_payment_form if $path =~ m|opac/myopac/main_payment_form|;
    return $self->load_myopac_payments if $path =~ m|opac/myopac/main_payments|;
    return $self->load_myopac_pay_init if $path =~ m|opac/myopac/main_pay_init|;
    return $self->load_myopac_pay if $path =~ m|opac/myopac/main_pay|;
    return $self->load_myopac_main if $path =~ m|opac/myopac/main|;
    return $self->load_myopac_receipt_email if $path =~ m|opac/myopac/receipt_email|;
    return $self->load_myopac_receipt_print if $path =~ m|opac/myopac/receipt_print|;
    return $self->load_myopac_update_email if $path =~ m|opac/myopac/update_email|;
    return $self->load_myopac_update_password if $path =~ m|opac/myopac/update_password|;
    return $self->load_myopac_update_username if $path =~ m|opac/myopac/update_username|;
    return $self->load_myopac_bookbags if $path =~ m|opac/myopac/lists|;
    return $self->load_myopac_bookbag_print if $path =~ m|opac/myopac/list/print|;
    return $self->load_myopac_bookbag_update if $path =~ m|opac/myopac/list/update|;
    return $self->load_myopac_circ_history_export if $path =~ m|opac/myopac/circ_history/export|;
    return $self->load_myopac_circ_history if $path =~ m|opac/myopac/circ_history|;
    return $self->load_myopac_hold_history if $path =~ m|opac/myopac/hold_history|;
    return $self->load_myopac_prefs_notify if $path =~ m|opac/myopac/prefs_notify|;
    return $self->load_myopac_prefs_settings if $path =~ m|opac/myopac/prefs_settings|;
    return $self->load_myopac_prefs_my_lists if $path =~ m|opac/myopac/prefs_my_lists|;
    return $self->load_myopac_prefs if $path =~ m|opac/myopac/prefs|;
    return $self->load_myopac_reservations if $path =~ m|opac/myopac/reservations|;
    return $self->load_sms_cn if $path =~ m|opac/sms_cn|;

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
    my $login_page = sprintf('%s://%s%s/login',($self->ctx->{is_staff} ? 'oils' : 'https'), $self->ctx->{hostname}, $self->ctx->{opac_root});
    my $redirect_to = uri_escape_utf8($self->apache->unparsed_uri);
    return $self->generic_redirect("$login_page?redirect_to=$redirect_to");
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

    $ctx->{physical_loc} = $self->get_physical_loc;

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
    $self->staff_saved_searches_set_expansion_state if $ctx->{is_staff};
    $self->load_eg_cache_hash;
    $self->load_copy_location_groups;
    $self->staff_saved_searches_set_expansion_state if $ctx->{is_staff};
    $self->load_search_filter_groups($ctx->{search_ou});
    $self->load_org_util_funcs;
    $self->load_perm_funcs;

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

# -----------------------------------------------------------------------------
# Log in and redirect to the redirect_to URL (or home)
# -----------------------------------------------------------------------------
sub load_login {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;

    $self->timelog("Load login begins");

    $ctx->{page} = 'login';

    my $username = $cgi->param('username') || '';
    $username =~ s/\s//g;  # Remove blanks
    my $password = $cgi->param('password');
    my $org_unit = $ctx->{physical_loc} || $ctx->{aou_tree}->()->id;
    my $persist = $cgi->param('persist');
    my $client_tz = $cgi->param('client_tz');

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

    my $response;
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

    return $self->generic_redirect(
        $cgi->param('redirect_to') || $acct,
        $cookie_list
    );
}

# -----------------------------------------------------------------------------
# Log out and redirect to the home page
# -----------------------------------------------------------------------------
sub load_logout {
    my $self = shift;
    my $redirect_to = shift || $self->cgi->param('redirect_to');

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

    return $self->generic_redirect(
        $redirect_to || $self->ctx->{home_page},
        [
            # clear value of and expire both of these login-related cookies
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
            )
        ]
    );
}

1;

