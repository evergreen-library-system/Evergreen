package OpenSRF::Application::Demo::Math;
use base qw/OpenSRF::Application/;
use OpenSRF::Application;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::DomainObject::oilsResponse;
use OpenSRF::DomainObject::oilsPrimitive;
use OpenSRF::EX qw/:try/;
use strict;
use warnings;

sub DESTROY{}

our $log = 'OpenSRF::Utils::Logger';

#sub method_lookup {
#
#	my( $class, $method_name, $method_proto ) = @_;
#
#	if( $method_name eq "add" ) {
#		return \&add;
#	}

#	if( $method_name eq "sub" ) {
#		return \&sub;
#	}
#
#	if( $method_name eq "mult" ) {
#		return \&mult;
#	}
#
#	if( $method_name eq "div" ) {
#		return \&div;
#	}

#	return undef;
#
#}

sub send_request {

	my $method_name = shift;
	my @params = @_;

	$log->debug( "Creating a client environment", DEBUG );
	my $session = OpenSRF::AppSession->create( 
			"dbmath", sysname => 'math', secret => '12345' );

	$log->debug( "Sending request to math server", INTERNAL );
	
	my $method = OpenSRF::DomainObject::oilsMethod->new( method => $method_name );
	
	$method->params( @params );
	

	my $req; 
	my $resp;
		

	try {

		for my $nn (0..1) {
			my $vv = $session->connect();
			if($vv) { last; }
			if( $nn and !$vv ) {
				throw OpenSRF::EX::CRITICAL ("DBMath connect attempt timed out");
			}
		}

		$req = $session->request( $method );
		$resp = $req->recv(10); 

	} catch OpenSRF::DomainObject::oilsAuthException with { 
		my $e = shift;
		$e->throw();
	}; 

	if ( defined($resp) and $resp and $resp->class->isa('OpenSRF::DomainObject::oilsResult') ){ 

		$log->debug( "Math server returned " . $resp->toString(1), INTERNAL );
		$req->finish;
		$session->finish;
		return $resp;

	} else {

		if( $resp ) { $log->debug( "Math received \n".$resp->toString(), ERROR ); }
		else{ $log->debug( "Math received empty value", ERROR ); }
		$req->finish;
		$session->finish;
		throw OpenSRF::EX::ERROR ("Did not receive expected data from MathDB");

	}
}


sub add_1_action { 1 };
sub add_1 {

	my $client = shift;
	my @args = @_;
	return send_request( "add", @args );
}

sub sub_1_action { 1 };
sub sub_1 {
	my $client = shift;
	my @args = @_;
	return send_request( "sub", @args );
}

sub mult_1_action { 1 };
sub mult_1 {
	my $client = shift;
	my @args = @_;
	return send_request( "mult", @args );
}

sub div_1_action { 1 };
sub div_1 {
	my $client = shift;
	my @args = @_;
	return send_request( "div", @args );
}


1;
