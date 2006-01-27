#!/usr/bin/perl

#----------------------------------------------------------------
# Code for testing the container API
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/ $apputils $memcache $user $authtoken $authtime /;
use strict; use warnings;

err("usage: $0 <config> <oils_login_username> ".
	" <oils_login_password> <patronid> <copy_barcode> [<type>]\n".
	"Where <type> is one of:\n".
	"\t'permit' to run the permit only\n".
	"\t'noncat_permit' to run the permit script against a noncat item\n".
	"\t'noncat' to check out a noncat item\n".
	"\tblahk to do a regular checkout\n" ) unless $ARGV[4];

my $config		= shift; 
my $username	= shift;
my $password	= shift;
my $patronid	= shift;
my $barcode		= shift;
my $type			= shift;

my $method = 'open-ils.circ.checkout_permit_';

sub go {
	osrf_connect($config);
	oils_login($username, $password);
	do_permit($patronid, $barcode, $type =~ /noncat/ ); 
	do_checkout($patronid, $barcode, $type =~ /noncat/ ) unless ($type =~ /permit/);
	oils_logout();
}

go();

#----------------------------------------------------------------


sub do_permit {
	my( $patronid, $barcode, $noncat ) = @_;

	my @args = ( $authtoken, 'patron', $patronid );
	push(@args, ('barcode', $barcode)) unless $noncat;
	push(@args, ('noncat', 1)) if $noncat;

	my $resp = simplereq( 
		CIRC(), 'open-ils.circ.permit_checkout_', @args );
	
	oils_event_die($resp);
	printl("Permit succeeded for patron $patronid");
}

sub do_checkout {
}

