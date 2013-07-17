#!perl

use Test::More tests => 4;

diag("Simple tests against the open-ils.auth service, memcached, and the stock test data.");

use strict;
use warnings;
use Data::Dumper;
use OpenSRF::System;
use OpenSRF::AppSession;
use Digest::MD5 qw(md5_hex);
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::SettingsClient;

# Some useful objects
our $cache      = "OpenSRF::Utils::Cache";
our $apputils   = "OpenILS::Application::AppUtils";
our $memcache;
our $authtoken;
our $authtime;

#----------------------------------------------------------------
# Exit a script
#----------------------------------------------------------------
sub err {
    my ($pkg, $file, $line, $sub)  = _caller();
    no warnings;
    die "Script halted with error ".
        "($pkg : $file : $line : $sub):\n" . shift() . "\n";
}

#----------------------------------------------------------------
# This is not the function you're looking for
#----------------------------------------------------------------
sub _caller {
    my ($pkg, $file, $line, $sub)  = caller(2);
    if(!$line) {
        ($pkg, $file, $line)  = caller(1);
        $sub = "";
    }
    return ($pkg, $file, $line, $sub);
}

#----------------------------------------------------------------
# Connect to the servers
#----------------------------------------------------------------
sub osrf_connect {
    my $config = `osrf_config --sysconfdir`;
    chomp $config;
    $config .= '/opensrf_core.xml';
    err("Bootstrap config required") unless $config;
    OpenSRF::System->bootstrap_client( config_file => $config );
}

#----------------------------------------------------------------
# Get a handle for the memcache object
#----------------------------------------------------------------
sub osrf_cache {
    $cache->use;
    $memcache = $cache->new('global') unless $memcache;
    return $memcache;
}

#----------------------------------------------------------------
# Is the given object an OILS event?
#----------------------------------------------------------------
sub oils_is_event {
    my $e = shift;
    if( $e and ref($e) eq 'HASH' ) {
        return 1 if defined($e->{ilsevent});
    }
    return 0;
}

#----------------------------------------------------------------
# If the given object is an event, this prints the event info 
# and exits the script
#----------------------------------------------------------------
sub oils_event_die {
    my $evt = shift;
    my ($pkg, $file, $line, $sub)  = _caller();
    if(oils_is_event($evt)) {
        if($evt->{ilsevent}) {
            diag("\nReceived Event($pkg : $file : $line : $sub): \n" . Dumper($evt));
            exit 1;
        }
    }
}

#----------------------------------------------------------------
# Login to the auth server and set the global $authtoken var
#----------------------------------------------------------------
sub oils_login {
    my( $username, $password, $type ) = @_;

    $type |= "staff";

    my $seed = $apputils->simplereq( 'open-ils.auth',
        'open-ils.auth.authenticate.init', $username );
    err("No auth seed") unless $seed;

    my $response = $apputils->simplereq( 'open-ils.auth',
        'open-ils.auth.authenticate.complete',
        {   username => $username,
            password => md5_hex($seed . md5_hex($password)),
            type => $type });

    err("No auth response returned on login") unless $response;

    oils_event_die($response);

    $authtime  = $response->{payload}->{authtime};
    $authtoken = $response->{payload}->{authtoken};
    diag("authtime is $authtime, authtoken is $authtoken");
    return $authtoken;
}

#----------------------------------------------------------------
# Destroys the login session on the server
#----------------------------------------------------------------
sub oils_logout {
    $apputils->simplereq(
        'open-ils.auth',
        'open-ils.auth.session.delete', (@_ ? shift : $authtoken) );
}

#----------------------------------------------------------------
# var $response = simplereq( $service, $method, @params );
#----------------------------------------------------------------
sub simplereq    { return $apputils->simplereq(@_); }
sub osrf_request { return $apputils->simplereq(@_); }

#----------------------------------------------------------------
# The tests...  assumes stock sample data, full-auto install by
# eg_wheezy_installer.sh, etc.
#----------------------------------------------------------------

osrf_connect();
oils_login('admin','demo123','staff');

ok(
    $authtoken,
    'Have an authtoken'
);
is(
    $authtime,
    7200,
    'Default authtime for staff login is 7200 seconds'
);

osrf_cache();
my $cached_obj = $memcache->get_cache("oils_auth_$authtoken");

ok(
    ref $cached_obj,
    'Can retrieve authtoken from memcached'
);

oils_logout();

$cached_obj = $memcache->get_cache("oils_auth_$authtoken");
ok(
    ! $cached_obj,
    'Authtoken is removed from memcached after logout'
);

