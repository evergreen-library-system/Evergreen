#!/usr/bin/perl -w
use strict;use warnings;
use OpenILS::System;
use OpenILS::DOM::Element::userAuth;
use OpenILS::Utils::Config;
use OpenILS::DomainObject::oilsMethod;
use OpenILS::DomainObject::oilsPrimitive;
use Time::HiRes qw/time/;
use OpenILS::EX qw/:try/;

$| = 1;

# ----------------------------------------------------------------------------------------
# This is a quick and dirty script to perform benchmarking against the math server.
# Note: 1 request performs a batch of 4 queries, one for each supported method: add, sub,
# mult, div.
# Usage: $ perl math_bench.pl <num_requests>
# ----------------------------------------------------------------------------------------


my $count = $ARGV[0];

unless( $count ) {
	print "usage: ./math_bench.pl <num_requests>\n";
	exit;
}

warn "PID: $$\n";

my $config = OpenILS::Utils::Config->current;
OpenILS::System->bootstrap_client();

my $session = OpenILS::AppSession->create( 
		"math", username => 'math_bench', secret => '12345' );

try {
	if( ! ($session->connect()) ) { die "Connect timed out\n"; }

} catch OpenILS::EX with {
	my $e = shift;
	warn "Connection Failed *\n";
	die $e;
}

my @times;
my %vals = ( add => 3, sub => -1, mult => 2, div => 0.5 );

for my $x (1..100) {
	if( $x % 10 ) { print ".";}
	else{ print $x/10; };
}
print "\n";

my $c = 0;

for my $scale ( 1..$count ) {
	for my $mname ( keys %vals ) {

		my $method = OpenILS::DomainObject::oilsMethod->new( method => $mname );
		$method->params( 1,2 );

		my $req;
		my $resp;
		my $starttime;
		try {

			$starttime = time();
			$req = $session->request( $method );
			$resp = $req->recv( timeout => 10 );
			push @times, time() - $starttime;

		} catch OpenILS::EX with {
			my $e = shift;
			die "ERROR\n $e";

		} catch Error with {
			my $e = shift;
			die "Caught unknown error: $e";
		};


		if( ! $req->complete ) { warn "\nIncomplete\n"; }


		if ( $resp ) {

			my $ret = $resp->content();
			if( "$ret" eq $vals{$mname} ) { print "+"; }

			else { print "*BAD*\n" . $resp->toString(1) . "\n"; }

		} else { print "*NADA*";	}

		$req->finish();
		$c++;

	}
	print "\n[$c] \n" unless $scale % 25;
}

$session->kill_me();

my $total = 0;

$total += $_ for (@times);

$total /= scalar(@times);

print "\n\n\tAverage Round Trip Time: $total Seconds\n";

