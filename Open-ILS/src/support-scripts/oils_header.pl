#!/usr/bin/perl

#----------------------------------------------------------------
# Generic header for tesing OpenSRF methods
#----------------------------------------------------------------

use strict;
use warnings;
use JSON;
use Data::Dumper;
use OpenSRF::System;
use OpenSRF::AppSession;
use OpenSRF::EX qw(:try);
use Time::HiRes qw/time/;
use Digest::MD5 qw(md5_hex);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw/:logger/;


# Some useful objects
our $apputils = "OpenILS::Application::AppUtils";
our $memcache;
our $user;
our $authtoken;
our $authtime;

# Some constants for our services
our $AUTH		= 'open-ils.auth';
our $STORAGE	= 'open-ils.storage';
our $SEARCH		= 'open-ils.search';
our $CIRC		= 'open-ils.circ';
our $CAT			= 'open-ils.cat';
our $MATH		= 'opensrf.math';
our $SETTINGS	= 'opensrf.settings';
our $ACTOR		= 'open-ils.actor';

sub AUTH		{ return $AUTH; }
sub STORAGE { return $STORAGE; }
sub SEARCH	{ return $SEARCH; }
sub CIRC		{ return $CIRC; }
sub CAT		{ return $CAT; }
sub MATH		{ return $MATH; }
sub SETTINGS { return $SETTINGS; }
sub ACTOR	{ return $ACTOR; }


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
# Print with newline
#----------------------------------------------------------------
sub printl { print "@_\n"; }

#----------------------------------------------------------------
# Print with Data::Dumper
#----------------------------------------------------------------
sub debug { printl(Dumper(@_)); }


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
	my $config = shift;
	err("Bootstrap config required") unless $config;
	OpenSRF::System->bootstrap_client( config_file => $config );
}

#----------------------------------------------------------------
# Get a handle for the memcache object
#----------------------------------------------------------------
sub osrf_cache { 
	eval 'use OpenSRF::Utils::Cache;';
	$memcache = OpenSRF::Utils::Cache->new('global') unless $memcache;
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
			printl("\nReceived Event($pkg : $file : $line : $sub): \n" . Dumper($evt));
			exit 1;
		}
	}
}


#----------------------------------------------------------------
# Login to the auth server and set the global $authtoken var
#----------------------------------------------------------------
sub oils_login {
	my( $username, $password ) = @_;

	my $seed = $apputils->simplereq( $AUTH, 
		'open-ils.auth.authenticate.init', $username );
	err("No auth seed") unless $seed;

	my $response = $apputils->simplereq( $AUTH, 
		'open-ils.auth.authenticate.complete', $username, 
		md5_hex($seed . md5_hex($password)), "staff");
	err("No auth response returned on login") unless $response;

	oils_event_die($response);

	$authtime = $response->{payload}->{authtime};
	$authtoken = $response->{payload}->{authtoken};
	return $authtoken;
}


#----------------------------------------------------------------
# Destroys the login session on the server
#----------------------------------------------------------------
sub oils_logout {
	$apputils->simplereq(
		'open-ils.auth',
		'open-ils.auth.session.delete', $authtoken );
}

#----------------------------------------------------------------
# Fetches the user object and sets the global $user var
#----------------------------------------------------------------
sub oils_fetch_session {
	my $ses = shift;
	my $resp = $apputils->simplereq( $AUTH, 
		'open-ils.auth.session.retrieve', $ses, 'staff' );
	oils_event_die($resp);
	return $user = $resp;
}

#----------------------------------------------------------------
# var $response = simplereq( $service, $method, @params );
#----------------------------------------------------------------
sub simplereq { return $apputils->simplereq(@_); }
sub osrf_request { return $apputils->simplereq(@_); }

1;
