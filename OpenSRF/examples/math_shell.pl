#!/usr/bin/perl -w
use strict;use warnings;
use OpenILS::System;
use OpenILS::Utils::Config;
use OpenILS::DomainObject::oilsMethod;
use OpenILS::DomainObject::oilsPrimitive;
use OpenILS::EX qw/:try/;
$| = 1;

# ----------------------------------------------------------------------------------------
# Simple math shell where you can test the transport system.
# Enter simple, binary equations ony using +, -, *, and /
# Example: # 1+1
# Usage: % perl math_shell.pl
# ----------------------------------------------------------------------------------------

# load the config
my $config = OpenILS::Utils::Config->current;

# connect to the transport (jabber) server
OpenILS::System->bootstrap_client();

# build the AppSession object.
my $session = OpenILS::AppSession->create( 
	"math", username => 'math_bench', secret => '12345' );

# launch the shell
print "type 'exit' or 'quit' to leave the shell\n";
print "# ";
while( my $request = <> ) {

	chomp $request ;

	# exit loop if user enters 'exit' or 'quit'
	if( $request =~ /exit/i or $request =~ /quit/i ) { last; }

	# figure out what the user entered
	my( $a, $mname, $b ) = parse_request( $request );

	if( $a =~ /error/ ) {
		print "Parse Error. Try again. \nExample # 1+1\n";
		next;
	}


	try {

		# Connect to the MATH server
		if( ! ($session->connect()) ) { die "Connect timed out\n"; }

	} catch OpenILS::EX with {
		my $e = shift;
		die "* * Connection Failed with:\n$e";
	};

	my $method = OpenILS::DomainObject::oilsMethod->new( method => $mname );
	$method->params( $a, $b );

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
		print $ret->value();
	}

	$req->finish();

	print "\n# ";

}

# disconnect from the MATH server
$session->kill_me();
exit;

# ------------------------------------------------------------------------------------
# parse the user input string
# returns a list of the form (first param, operation, second param)
# These operations are what the MATH server recognizes as method names
# ------------------------------------------------------------------------------------
sub parse_request {
	my $string = shift;
	my $op;
	my @ops;
	
	while( 1 ) {

		@ops = split( /\+/, $string );
		if( @ops > 1 ) { $op = "add"; last; }

		@ops = split( /\-/, $string );
		if( @ops > 1 ) { $op = "sub"; last; }

		@ops = split( /\*/, $string );
		if( @ops > 1 ) { $op = "mult", last; }

		@ops = split( /\//, $string );
		if( @ops > 1 ) { $op = "div"; last; }

		return ("error");
	}

	return ($ops[0], $op, $ops[1]);
}

