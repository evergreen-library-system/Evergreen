#!/usr/bin/perl

#----------------------------------------------------------------
# Code for testing the container API
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/ $apputils $memcache $user $authtoken $authtime /;
use strict; use warnings;

#----------------------------------------------------------------
err("\nusage: $0 <config> <oils_login_username> ".
	" <oils_login_password> <patronid> <copy_barcode> [<type>, <noncat_type>]\n".
	"Where <type> is one of:\n".
	"\t'permit' to run the permit only\n".
	"\t'noncat_permit' to run the permit script against a noncat item\n".
	"\t'noncat' to check out a noncat item\n".
	"\t(blank) to do a regular checkout\n" ) unless $ARGV[5];
#----------------------------------------------------------------

my $config		= shift; 
my $username	= shift;
my $password	= shift;
my $patronid	= shift;
my $barcode		= shift;
my $type			= shift;
my $nc_type		= shift;

sub go {
	osrf_connect($config);
	oils_login($username, $password);
	do_permit($patronid, $barcode, $type =~ /noncat/ ); 
	do_checkout($patronid, $barcode, $type =~ /noncat/, $nc_type ) unless ($type =~ /permit/);
	oils_logout();
}

go();

#----------------------------------------------------------------

sub do_permit {
	my( $patronid, $barcode, $noncat ) = @_;

	my @args = ( $authtoken, 'patron', $patronid );
	push(@args, (barcode => $barcode)) unless $noncat;
	push(@args, (noncat => 1, noncat_type => $nc_type) ) if $noncat;

	my $resp = simplereq( 
		CIRC(), 'open-ils.circ.checkout.permit', @args );
	
	oils_event_die($resp);
	printl("Permit succeeded for patron $patronid");
}

sub do_checkout {
	my( $patronid, $barcode, $noncat, $nc_type ) = @_;

	my @args = ($authtoken, 'patron', $patronid);
	push(@args, (barcode => $barcode)) unless $noncat;
	push(@args, noncat => 1, noncat_type => $nc_type ) if $noncat;

	my $resp = osrf_request(
		'open-ils.circ', 
		'open-ils.circ.checkout', @args );
	oils_event_die($resp);
	printl("Checkout succeeded");
}




