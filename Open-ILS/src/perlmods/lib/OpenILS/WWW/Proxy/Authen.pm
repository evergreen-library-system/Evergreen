package OpenILS::WWW::Proxy::Authen;
use strict; use warnings;

use Apache2::Access;
use Apache2::RequestUtil;
use Apache2::Log;
use Apache2::Const -compile => qw(OK HTTP_UNAUTHORIZED DECLINED HTTP_MOVED_TEMPORARILY NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use CGI;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;

use OpenSRF::EX qw(:try);
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;

# set the bootstrap config when 
# this module is loaded
my $bootstrap;
my $ssl_off;

sub import {
    my $self = shift;
    $bootstrap = shift;
    $ssl_off = shift;
}


sub child_init {
    OpenSRF::System->bootstrap_client( config_file => $bootstrap );
    return Apache2::Const::OK;
}

sub handler {
    my $apache = shift;

    my $ltype = $apache->dir_config('OILSProxyLoginType');
    my $context_mode = $apache->dir_config('OILSProxyContextMode');
    my $perms = [ split ' ', $apache->dir_config('OILSProxyPermissions') ];

    return Apache2::Const::NOT_FOUND unless (@$perms);

    my $cgi = new CGI;
    my $auth_ses = $cgi->param('ses') || $cgi->cookie('ses') || $cgi->cookie('eg.auth.token');
    if ($auth_ses =~ /^"(.+)"$/) { # came from eg2 login, is json encoded
        $auth_ses = $1;
    }

    # Note that the handler accepts an eg.auth.token from the web staff
    # client but will not set it if it has to ask the user for
    # credentials (it will only set 'ses'). As of 2022-11, it works this
    # way to avoid this authen handler from becoming a way to create
    # a staff login session that does not have a workstation set.

    my $ws_ou = $apache->dir_config('OILSProxyLoginOU') || $cgi->param('ws_ou') || $cgi->cookie('ws_ou');

    my $url = $cgi->url;
    my $bad_auth = 1; # Assume failure until proven otherwise ;)

    # push everyone to the secure site
    if (!$ssl_off && $url =~ /^http:/o) {
        my $base = $cgi->url(-base=>1);
        $base =~ s/^http:/https:/o;
        $apache->headers_out->set(Location => $base . $apache->unparsed_uri);
        return Apache2::Const::HTTP_MOVED_TEMPORARILY;
    }

    my $tried_login = 0;
    my $cookie;

    while ($bad_auth && $tried_login == 0) {
        if (!$auth_ses) {
            $tried_login = 1;
            my ($status, $p) = $apache->get_basic_auth_pw;
            my $u;
            if ($status == Apache2::Const::OK) {
                $u = $apache->user;
            } else {
                $u = $cgi->param('user');
                $p = $cgi->param('passwd');
                return $status if (!$u);
            }
    
            if ($u) {
                $auth_ses = oils_login($u, $p, $ltype);
                if ($auth_ses) {
                    $cookie = $cgi->cookie(
                        -name=>'ses',
                        -value=>$auth_ses,
                        -path=>'/',
                        -secure=>1
                    );
                }
            }
        }
    
        my $user = verify_login($auth_ses);
    
        if ($user) {
            $ws_ou ||= $user->home_ou;
    
            $logger->debug("Checking perms " . join(',', @$perms) . " for user " . $user->id . " at location $ws_ou\n");
    
            my $failures = OpenSRF::AppSession
                ->create('open-ils.actor')
                ->request('open-ils.actor.user.perm.check', $auth_ses, $user->id, $ws_ou, $perms)
                ->gather(1);
    
            if ($context_mode eq 'reporter') {
                my @uri_parts = split '/', $apache->uri;
                my $output_id = $uri_parts[-2]; # /reporter/$tid/$rid/$oid/part.of.the.output.html
                $logger->debug("Additionally checking output visibility of $output_id for user " . $user->id);

                my $is_visible = OpenSRF::AppSession
                    ->create('open-ils.reporter')
                    ->request('open-ils.reporter.output_visible', $auth_ses, $output_id, @$perms)
                    ->gather(1);
                push(@$failures, 1) if (!$is_visible);
            }

            if (@$failures > 0) {
                $cookie = $cgi->cookie(
                        -name=>'ses',
                        -value=>'',
                        -path=>'/',
                        -expires=>'-1h'
                );
            } else {
                # it appears that as of Apache 2.4, authentication
                # handlers are expected to ensure that the request
                # object has ->user set.
                $apache->user($user->usrname);
                $bad_auth = 0;
            }
        }

        $auth_ses = undef if($bad_auth && !$tried_login);
    }

    if ($bad_auth) {
        $apache->err_headers_out->add('Set-Cookie' => $cookie) if($cookie);
        $apache->note_basic_auth_failure;
        return Apache2::Const::HTTP_UNAUTHORIZED;
    }

    if ($tried_login) {
        # We authenticated, and thus likely got a new auth key.
        # Set it and redirect in case what we are protecting needs the key.

        # When not redirecting we don't need the err_ variant of this. Noting for reference.
        $apache->err_headers_out->add('Set-Cookie' => $cookie) if($cookie);
        my $base = $cgi->url(-base=>1);
        $apache->headers_out->set(Location => $base . $apache->unparsed_uri);
        return Apache2::Const::HTTP_MOVED_TEMPORARILY;
    }

    # they're good, let 'em through
    return Apache2::Const::OK;
}

# returns the user object if the session is valid, 0 otherwise
sub verify_login {
    my $auth_token = shift;
    return undef unless $auth_token;

    my $user = OpenSRF::AppSession
        ->create("open-ils.auth")
        ->request( "open-ils.auth.session.retrieve", $auth_token )
        ->gather(1);

    if (ref($user) eq 'HASH' && $user->{ilsevent} == 1001) {
        return undef;
    }

    return $user if ref($user);
    return undef;
}

sub oils_login {
        my( $username, $password, $type ) = @_;

        $type |= "staff";
    my $nametype = 'username';
    $nametype = 'barcode' if ($username =~ /^\d+$/o);

        my $seed = OpenSRF::AppSession
        ->create("open-ils.auth")
        ->request( 'open-ils.auth.authenticate.init', $username )
        ->gather(1);

        return undef unless $seed;

        my $response = OpenSRF::AppSession
        ->create("open-ils.auth")
        ->request( 'open-ils.auth.authenticate.complete',
            { $nametype => $username, agent => 'authproxy',
              password => md5_hex($seed . md5_hex($password)),
              type => $type })
        ->gather(1);

        return undef unless $response;

        return $response->{payload}->{authtoken};
}

1;

