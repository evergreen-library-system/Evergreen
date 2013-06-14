package OpenILS::Reporter::Proxy;
use strict; use warnings;

use Apache2::Log;
use Apache2::Const -compile => qw(REDIRECT FORBIDDEN OK NOT_FOUND DECLINED :log);
use APR::Const    -compile => qw(:error SUCCESS);
use CGI;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;

use OpenSRF::EX qw(:try);
use OpenSRF::System;


# set the bootstrap config and template include directory when 
# this module is loaded
my $bootstrap;

sub import {
    my $self = shift;
    $bootstrap = shift;
}


sub child_init {
    OpenSRF::System->bootstrap_client( config_file => $bootstrap );
}

sub handler {
    my $apache = shift;
    my $cgi = new CGI;
    my $auth_ses = $cgi->cookie('ses');
    my $ws_ou = $cgi->cookie('ws_ou') || 1;

    my $url = $cgi->url;

    # push everyone to the secure site
    if ($url =~ /^http:/o) {
        $url =~ s/^http:/https:/o;
        print "Location: $url\n\n";
        return Apache2::Const::OK;
    }

    if (!$auth_ses) {
        my $u = $cgi->param('user');
        my $p = $cgi->param('passwd');

        if (!$u) {

            print $cgi->header(-type=>'text/html', -expires=>'-1d');
            print <<"            HTML";

<html>
    <head>
        <title>Report Output Login</title>
    </head>
    <body>
        <br/><br/><br/>
        <center>
        <form method='POST'>
            <table style='border-collapse: collapse; border: 1px solid black;'>
                <tr>
                    <th colspan='2' align='center'><u>Please log in to view reports</u></th>
                </tr>
                <tr>
                    <th align="right">Username or barcode:</th>
                    <td><input type="text" name="user"/></td>
                </tr>
                <tr>
                    <th align="right">Password:</th>
                    <td><input type="password" name="passwd"/></td>
                </tr>
            </table>
            <input type="submit" value="Log in"/>
        </form>
        </center>
    </body>
</html>

            HTML
            return Apache2::Const::OK;
        }

        $auth_ses = oils_login($u, $p);
        if ($auth_ses) {
            print $cgi->redirect(
                -uri=>$url,
                -cookie=>$cgi->cookie(
                    -name=>'ses',
                    -value=>$auth_ses,
                    -path=>'/',-expires=>'+1h'
                )
            );
            return Apache2::Const::REDIRECT;
        }
    }

    my $user = verify_login($auth_ses);
    return Apache2::Const::FORBIDDEN unless ($user);

    my $failures = OpenSRF::AppSession
        ->create('open-ils.actor')
        ->request('open-ils.actor.user.perm.check', $auth_ses, $user->id, $ws_ou, ['VIEW_REPORT_OUTPUT'])
        ->gather(1);

    return Apache2::Const::FORBIDDEN if (@$failures > 0);

    # they're good, let 'em through
    return Apache2::Const::DECLINED if (-e $apache->filename);

    # oops, file not found
    return Apache2::Const::NOT_FOUND;
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
            { $nametype => $username,
              password => md5_hex($seed . md5_hex($password)),
              type => $type })
        ->gather(1);

        return undef unless $response;

        return $response->{payload}->{authtoken};
}



1;
