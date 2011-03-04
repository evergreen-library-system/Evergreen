package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use CGI;
use XML::LibXML;
use URI::Escape;
use Digest::MD5 qw(md5_hex);
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use DateTime::Format::ISO8601;

# EGCatLoader sub-modules 
use OpenILS::WWW::EGCatLoader::Util;
use OpenILS::WWW::EGCatLoader::Account;
use OpenILS::WWW::EGCatLoader::Search;
use OpenILS::WWW::EGCatLoader::Record;
use OpenILS::WWW::EGCatLoader::Container;

my $U = 'OpenILS::Application::AppUtils';

use constant COOKIE_SES => 'ses';

sub new {
    my($class, $apache, $ctx) = @_;

    my $self = bless({}, ref($class) || $class);

    $self->apache($apache);
    $self->ctx($ctx);
    $self->cgi(CGI->new);

    OpenILS::Utils::CStoreEditor->init; # just in case
    $self->editor(new_editor());

    return $self;
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


# -----------------------------------------------------------------------------
# Perform initial setup, load common data, then load page data
# -----------------------------------------------------------------------------
sub load {
    my $self = shift;

    $self->init_ro_object_cache;

    my $stat = $self->load_common;
    return $stat unless $stat == Apache2::Const::OK;

    my $path = $self->apache->path_info;

    return $self->load_simple("home") if $path =~ /opac\/home/;
    return $self->load_simple("advanced") if $path =~ /opac\/advanced/;
    return $self->load_rresults if $path =~ /opac\/results/;
    return $self->load_record if $path =~ /opac\/record/;
    return $self->load_mylist_add if $path =~ /opac\/mylist\/add/;
    return $self->load_mylist_del if $path =~ /opac\/mylist\/del/;
    return $self->load_cache_clear if $path =~ /opac\/cache\/clear/;

    # ----------------------------------------------------------------
    # Logout and login require SSL
    # ----------------------------------------------------------------
    if($path =~ /opac\/login/) {
        return $self->redirect_ssl unless $self->cgi->https;
        return $self->load_login;
    }

    if($path =~ /opac\/logout/) {
        #return Apache2::Const::FORBIDDEN unless $self->cgi->https; 
        $self->apache->log->warn("catloader: logout called in non-secure context from " . 
            ($self->ctx->{referer} || '<no referer>')) unless $self->cgi->https;
        return $self->load_logout;
    }

    # ----------------------------------------------------------------
    #  Everything below here requires SSL + authentication
    # ----------------------------------------------------------------
    return $self->redirect_auth
        unless $self->cgi->https and $self->editor->requestor;

    return $self->load_place_hold if $path =~ /opac\/place_hold/;
    return $self->load_myopac_holds if $path =~ /opac\/myopac\/holds/;
    return $self->load_myopac_circs if $path =~ /opac\/myopac\/circs/;
    return $self->load_myopac_fines if $path =~ /opac\/myopac\/main/;
    return $self->load_myopac_update_email if $path =~ /opac\/myopac\/update_email/;
    return $self->load_myopac_bookbags if $path =~ /opac\/myopac\/lists/;
    return $self->load_myopac_bookbag_update if $path =~ /opac\/myopac\/list\/update/;
    return $self->load_myopac if $path =~ /opac\/myopac/;

    return Apache2::Const::OK;
}


# -----------------------------------------------------------------------------
# Redirect to SSL equivalent of a given page
# -----------------------------------------------------------------------------
sub redirect_ssl {
    my $self = shift;
    my $new_page = sprintf('https://%s%s', $self->apache->hostname, $self->apache->unparsed_uri);
    return $self->generic_redirect($new_page);
}

# -----------------------------------------------------------------------------
# If an authnticated resource is requested w/o auth, redirect to the login page,
# then return to the originally requrested resource upon successful login.
# -----------------------------------------------------------------------------
sub redirect_auth {
    my $self = shift;
    my $login_page = sprintf('https://%s%s/login', $self->apache->hostname, $self->ctx->{opac_root});
    my $redirect_to = uri_escape($self->apache->unparsed_uri);
    return $self->generic_redirect("$login_page?redirect_to=$redirect_to");
}

# -----------------------------------------------------------------------------
# Fall-through for loading a basic page
# -----------------------------------------------------------------------------
sub load_simple {
    my ($self, $page) = @_;
    $self->ctx->{page} = $page;
    return Apache2::Const::OK;
}

# -----------------------------------------------------------------------------
# Tests to see if the user is authenticated and sets some common context values
# -----------------------------------------------------------------------------
sub load_common {
    my $self = shift;

    my $e = $self->editor;
    my $ctx = $self->ctx;

    $ctx->{referer} = $self->cgi->referer;
    $ctx->{path_info} = $self->cgi->path_info;
    $ctx->{opac_root} = $ctx->{base_path} . "/opac"; # absolute base url
    $ctx->{is_staff} = ($self->apache->headers_in->get('User-Agent') =~ 'oils_xulrunner');

    # capture some commonly accessed pages
    $ctx->{home_page} = 'http://' . $self->apache->hostname . $self->ctx->{opac_root} . "/home";
    $ctx->{logout_page} = 'https://' . $self->apache->hostname . $self->ctx->{opac_root} . "/logout";

    if($e->authtoken($self->cgi->cookie(COOKIE_SES))) {

        if($e->checkauth) {

            $ctx->{authtoken} = $e->authtoken;
            $ctx->{authtime} = $e->authtime;
            $ctx->{user} = $e->requestor;

            $ctx->{user_stats} = $U->simplereq(
                'open-ils.actor', 
                'open-ils.actor.user.opac.vital_stats', 
                $e->authtoken, $e->requestor->id);

        } else {

            # For now, keep an eye out for any pages being unceremoniously redirected to logout...
            $self->apache->log->info("catloader: loading " . $ctx->{path_info} . 
                "; auth session " .  $e->authtoken . " no longer valid; redirecting to logout");

            return $self->load_logout;
        }
    }

    return Apache2::Const::OK;
}


# -----------------------------------------------------------------------------
# Log in and redirect to the redirect_to URL (or home)
# -----------------------------------------------------------------------------
sub load_login {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;

    $ctx->{page} = 'login';

    my $username = $cgi->param('username');
    my $password = $cgi->param('password');
    my $org_unit = $cgi->param('loc') || $ctx->{aou_tree}->()->id;
    my $persist = $cgi->param('persist');

    # initial log form only
    return Apache2::Const::OK unless $username and $password;

	my $seed = $U->simplereq(
        'open-ils.auth', 
		'open-ils.auth.authenticate.init', $username);

    my $args = {	
        username => $username, 
        password => md5_hex($seed . md5_hex($password)), 
        type => ($persist) ? 'persist' : 'opac' 
    };

    my $bc_regex = $ctx->{get_org_setting}->($org_unit, 'opac.barcode_regex');

    $args->{barcode} = delete $args->{username} 
        if $bc_regex and $username =~ /$bc_regex/;

	my $response = $U->simplereq(
        'open-ils.auth', 'open-ils.auth.authenticate.complete', $args);

    if($U->event_code($response)) { 
        # login failed, report the reason to the template
        $ctx->{login_failed_event} = $response;
        return Apache2::Const::OK;
    }

    # login succeeded, redirect as necessary

    my $acct = $self->apache->unparsed_uri;
    $acct =~ s#/login#/myopac/main#;

    return $self->generic_redirect(
        $cgi->param('redirect_to') || $acct,
        $cgi->cookie(
            -name => COOKIE_SES,
            -path => '/',
            -secure => 1,
            -value => $response->{payload}->{authtoken},
            -expires => ($persist) ? CORE::time + $response->{payload}->{authtime} : undef
        )
    );
}

# -----------------------------------------------------------------------------
# Log out and redirect to the home page
# -----------------------------------------------------------------------------
sub load_logout {
    my $self = shift;

    # If the user was adding anyting to an anonymous cache 
    # while logged in, go ahead and clear it out.
    $self->clear_anon_cache;

    return $self->generic_redirect(
        $self->ctx->{home_page},
        $self->cgi->cookie(
            -name => COOKIE_SES,
            -path => '/',
            -value => '',
            -expires => '-1h'
        )
    );
}

1;

