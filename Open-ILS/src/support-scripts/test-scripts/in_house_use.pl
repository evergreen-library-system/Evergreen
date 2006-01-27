#!/usr/bin/perl

#----------------------------------------------------------------
# Code for testing the container API
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/ $apputils $memcache $user $authtoken $authtime /;
use strict; use warnings;

#----------------------------------------------------------------
err("\nusage: $0 <config> <oils_username>  <oils_password> <copyid> <org_id> [<count>]\n".
	"If <count> is defined, then <count> in-house uses will be ".
	"created for the copy, otherwise 1 is created" ) unless $ARGV[4];
#----------------------------------------------------------------

my $config		= shift; 
my $username	= shift;
my $password	= shift;
my $copyid		= shift;
my $location	= shift;
my $count		= shift || 1;

my $method = 'open-ils.circ.in_house_use.create';

sub go {
	osrf_connect($config);
	oils_login($username, $password);
	do_in_house_use($copyid, $location, $count);
	oils_logout();
}

go();

#----------------------------------------------------------------


sub do_in_house_use {
	my( $copyid, $location, $count ) = @_;
	my $resp = simplereq(
		'open-ils.circ',
		'open-ils.circ.in_house_use.create', $authtoken, 
		copyid	=> $copyid, 
		location	=> $location, 
		count		=> $count );

	oils_event_die($resp);
	printl("Successfully created " . scalar(@$resp) . " in house \n".
	"use actions for copy $copyid and location $location");
}

