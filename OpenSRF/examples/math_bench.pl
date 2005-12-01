#!/usr/bin/perl
use strict; use warnings;
use OpenSRF::System;
use Time::HiRes qw/time/;
use OpenSRF::Utils::Logger;
my $log = "OpenSRF::Utils::Logger";

# Test script which runs queries agains the opensrf.math service and reports on
# the average round trip time of the requests.

# how many batches of 4 requests do we send
my $count = $ARGV[0];
print "usage: $0 <num_requests>\n" and exit unless $count;

# * connect to the Jabber network
OpenSRF::System->bootstrap_client( config_file => "/openils/conf/bootstrap.conf" );
$log->set_service('math_bench');

# * create a new application session for the opensrf.math service
my $session = OpenSRF::AppSession->create( "opensrf.math" );

my @times; # "delta" times for each round trip

# we're gonna call methods "add", "sub", "mult", and "div" with
# params 1, 2.  The hash below maps the method name to the 
# expected response value
my %vals = ( add => 3, sub => -1, mult => 2, div => 0.5 );

# print the counter grid 
for my $x (1..100) {
	if( $x % 10 ) { print ".";}
	else{ print $x/10; };
}
print "\n";

my $c = 0;

for my $scale ( 1..$count ) {
	for my $mname ( keys %vals ) { # cycle through add, sub, mult, and div

		my $starttime = time();

		# * Fires the request and gathers the response object, which in this case
		# is just a string
		my $resp = $session->request( $mname, 1, 2 )->gather(1);
		push @times, time() - $starttime;


		if( "$resp" eq $vals{$mname} ) { 
			# we got the response we expected
			print "+"; 

		} elsif($resp) { 
			# we got some other response	 
			print "\n* BAD Data:  $resp\n";

		} else { 
			# we got no data
			print "Received nothing\n";	
		}

		$c++;

	}

	print " [$c] \n" unless $scale % 25;
}

my $total = 0;

$total += $_ for (@times);

$total /= scalar(@times);

print "\n\n\tAverage Round Trip Time: $total Seconds\n";


