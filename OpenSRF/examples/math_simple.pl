#!/usr/bin/perl -w
use strict;use warnings;
use OpenILS::System;
use OpenILS::Utils::Config;
use OpenILS::DomainObject::oilsMethod;
use OpenILS::DomainObject::oilsPrimitive;
use OpenILS::EX qw/:try/;
$| = 1;


# ----------------------------------------------------------------------------------------
# This script makes a single query, 1 + 2,  to the the MATH test app and prints the result
# Usage: % perl math_simple.pl 
# ----------------------------------------------------------------------------------------


# connect to the transport (jabber) server
OpenILS::System->bootstrap_client();

# build the AppSession object.
my $session = OpenILS::AppSession->create( 
	"math", username => 'math_bench', secret => '12345' );

try {

	# Connect to the MATH server
	if( ! ($session->connect()) ) { die "Connect timed out\n"; }

} catch OpenILS::EX with {
	my $e = shift;
	die "* * Connection Failed with:\n$e";
};

my $method = OpenILS::DomainObject::oilsMethod->new( method => "add" );
$method->params( 1, 2 );

my $req;
my $resp;

try {
	$req = $session->request( $method );

	# we know that this request only has a single reply
	# if your expecting a 'stream' of results, you can
	# do: while( $resp = $req->recv( timeout => 10 ) ) {}
	$resp = $req->recv( timeout => 10 );

} catch OpenILS::EX with {

	# Any transport layer or server problems will launch an exception
	my $e = shift;
	die "ERROR Receiving\n $e";

} catch Error with {

	# something just died somethere
	my $e = shift;
	die "Caught unknown error: $e";
};

if ( $resp ) {
	# ----------------------------------------------------------------------------------------
	# $resp is an OpenILS::DomainObject::oilsResponse object. $resp->content() returns whatever 
	# data the object has.  If the server returns an exception that we're meant to see, then
	# the data will be an exception object.  In this case, barring any exception, we know that 
	# the data is an OpenILS::DomainObject::oilsScalar object which has a value() method 
	# that returns a perl scalar.  For us, that scalar is just a number.
	# ----------------------------------------------------------------------------------------

	if( UNIVERSAL::isa( $resp, "OpenILS::EX" ) ) {
			throw $resp;
	}

	my $ret = $resp->content();
	print "Should print 3 => " . $ret->value() . "\n";

} else {
	die "No Response from Server!\n";
}

$req->finish();

# disconnect from the MATH server
$session->kill_me();
exit;

