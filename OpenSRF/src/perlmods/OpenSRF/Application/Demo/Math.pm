package OpenSRF::Application::Demo::Math;
use base qw/OpenSRF::Application/;
use OpenSRF::Application;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::DomainObject::oilsResponse;
#use OpenSRF::DomainObject::oilsPrimitive;
use OpenSRF::EX qw/:try/;
use strict;
use warnings;

sub DESTROY{}

our $log = 'OpenSRF::Utils::Logger';

sub send_request {
	my $self = shift;
	my $client = shift;

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
		if( $resp ) {
			throw OpenSRF::EX::ERROR ("Did not receive expected data from MathDB\n" . $resp);
		} else {
			throw OpenSRF::EX::ERROR ("Received no data from MathDB");
		}

	}
}
__PACKAGE__->register_method( method => 'send_request', api_name => '_send_request' );

__PACKAGE__->register_method( method => 'add_1', api_name => 'add' );
sub add_1 {
	my $self = shift;
	my $client = shift;
	my @args = @_;

	my $meth = $self->method_lookup('_send_request');
	my ($result) = $meth->run('add',@args);

	return $result;
	
	return send_request( "add", @args );
}

__PACKAGE__->register_method( method => 'sub_1', api_name => 'sub' );
sub sub_1 {
	my $self = shift;
	my $client = shift;
	my @args = @_;

	my $meth = $self->method_lookup('_send_request');
	my ($result) = $meth->run('sub',@args);

	return $result;
	
	return send_request( "sub", @args );
}

__PACKAGE__->register_method( method => 'mult_1', api_name => 'mult' );
sub mult_1 {
	my $self = shift;
	my $client = shift;
	my @args = @_;

	my $meth = $self->method_lookup('_send_request');
	my ($result) = $meth->run('mult',@args);

	return $result;
	
	return send_request( "mult", @args );
}

__PACKAGE__->register_method( method => 'div_1', api_name => 'div' );
sub div_1 {
	my $self = shift;
	my $client = shift;
	my @args = @_;

	my $meth = $self->method_lookup('_send_request');
	my ($result) = $meth->run('div',@args);

	return $result;
	
	return send_request( "div", @args );
}


1;
