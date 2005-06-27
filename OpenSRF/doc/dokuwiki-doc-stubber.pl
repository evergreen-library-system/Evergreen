#!/usr/bin/perl -w
use OpenSRF::System qw(/pines/conf/bootstrap.conf);
use Data::Dumper;

$| = 1;

# ----------------------------------------------------------------------------------------
# This is a quick and dirty script to perform benchmarking against the math server.
# Note: 1 request performs a batch of 4 queries, one for each supported method: add, sub,
# mult, div.
# Usage: $ perl math_bench.pl <num_requests>
# ----------------------------------------------------------------------------------------


my $count = $ARGV[0];

unless( $count ) {
	print "usage: $0 <service name> [<cvs repo base URL>]\n";
	exit;
}

my $cvs_base = $ARGV[1] || 'http://open-ils.org/cgi-bin/viewcvs.cgi/ILS/Open-ILS/src/perlmods/';

OpenSRF::System->bootstrap_client();
my $session = OpenSRF::AppSession->create( $ARGV[0] );

my $req = $session->request('opensrf.system.method.all');

while( my $meth = $req->recv(60) ) {
	$meth = $meth->content;
	my $api_name = $meth->{api_name};
	my $api_level = int $meth->{api_level};
	my $server_class = $meth->{server_class} || '**ALL**';
	my $stream = int($meth->{stream} || 0);
	my $cachable = int($meth->{cachable} || 0);
	my $note = $meth->{note} || 'what I do';
	my $package = $meth->{package};
	(my $cvs = $package) =~ s/::/\//go;
	my $method = $meth->{method};

	$stream = $stream?'Yes':'No';
	$cachable = $cachable?'Yes':'No';

	print <<"	METHOD";
===== $api_name =====

$note

  * [[osrf-devel:terms#opensrf_api-level|API Level]]: $api_level
  * [[osrf-devel:terms#opensrf_server_class|Server Class]]: $server_class
  * Implementation Method: [[$cvs_base/$cvs.pm|$package\::$method]]
  * Streaming [[osrf-devel:terms#opensrf_method|Method]]: $stream
  * Cachable [[osrf-devel:terms#opensrf_method|Method]]: $cachable

  * **Parameters:**
    * //param1//\\\\ what it is...
  * **Returns:**
    * //Success//\\\\ successful format
    * //Failure//\\\\ failure format (exception, etc)


	METHOD
}

