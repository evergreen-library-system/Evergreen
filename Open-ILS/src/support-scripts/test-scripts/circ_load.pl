#!/usr/bin/perl

#----------------------------------------------------------------
# Code for testing the container API
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/ $authtoken /;
use strict; use warnings;
use Time::HiRes qw/time usleep/;

#----------------------------------------------------------------
err("\nusage: $0 <config> <oils_login_username> <oils_login_password> ".
	"<patronid> <barcode_file> <num_iterations> <num_processes>\n" .
	"<barcode_file> is a file with a single copy barcode per line") unless $ARGV[6];
#----------------------------------------------------------------

my $config		= shift; 
my $username	= shift;
my $password	= shift;
my $patronid	= shift;
my $barcodes	= shift;
my $numiters	= shift;
my $numprocs	= shift;

open(F,$barcodes);
my @BARCODES = <F>;
close(F);

$numprocs = ($numprocs and $numprocs < 50) ? $numprocs : 1;

print "start time = " . time . "\n";

my $index = 0;
for(1..($numprocs - 1)) {
	last if fork();
	$index++;
	sleep(2); # this gives auth time to work
}

go($index);

sub go {
	my $index = shift;
	my $barcode = $BARCODES[$index];
	chomp $barcode;

	osrf_connect($config);
	oils_login($username, $password);

	printl("$$ running barcode $barcode");

	my $s = time;

	for(1..$numiters) {
		my $start = time;
		my $key  = do_permit($patronid, $barcode ); 
		die "permit failed\n" unless $key;
		do_checkout($key, $patronid, $barcode );
		printl("checkout time = " . (time - $start));
		$start = time;
		do_checkin($barcode);
		printl("checkin time = " . (time - $start));
	}

	print "\nchild $index, iterations = $numiters, total time = " . (time - $s) . ", current time = " . time . "\n";
}

#----------------------------------------------------------------

sub do_permit {
	my( $patronid, $barcode ) = @_;

	my $args = { patron => $patronid, barcode => $barcode };

	my $resp = simplereq( 
		CIRC(), 'open-ils.circ.checkout.permit', $authtoken, $args );

	oils_event_die($resp);	 
	
	if( ref($resp) eq 'ARRAY' ) { # we received a list of non-success events
		printl("received event: ".$_->{textcode}) for @$resp;
		return undef;
	} 

	return $resp->{payload};
}


sub do_checkout {
	my( $key, $patronid, $barcode ) = @_;
	my $args = { permit_key => $key, patron => $patronid, barcode => $barcode };
	my $resp = osrf_request(
		'open-ils.circ', 
		'open-ils.circ.checkout', $authtoken, $args );
	oils_event_die($resp);
}


sub do_checkin {
	my $barcode  = shift;
	my $args = { barcode => $barcode };
	my $resp = simplereq( 
		CIRC(), 'open-ils.circ.checkin', $authtoken, $args );
	oils_event_die($resp);
	debug($resp) if(ref($resp) eq 'ARRAY');
}


