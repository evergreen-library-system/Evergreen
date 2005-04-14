package OpenILS::Application::Proxy;
use strict; use warnings;
use base qw/OpenSRF::Application/;
use OpenSRF::EX qw(:try);


__PACKAGE__->register_method(
	method	=> "proxy",
	api_name	=> "open-ils.proxy.proxy",
);


sub proxy {
	my($self, $client, $user_session, 
			$server, $method, @params) = @_;

	warn "$user_session - $server - $method\n";

	throw OpenSRF::EX::ERROR ("Not enough args to proxy")
		unless ($user_session and $server and $method);


	my $session = OpenSRF::AppSession->create($server);
	my $request = $session->request( $method, @params );
	if(!$request) {
		throw OpenSRF::EX::ERROR 
			("No request built on call to session->request( $method, @params )");
	}
	
	$request->wait_complete;

	if( $request->failed() ) { 

		throw OpenSRF::EX::ERROR
			($request->failed()->stringify());

	} else {

		while( my $response = $request->recv ) {
			$client->respond( $response->content );
		}
	}

	$request->finish();
	$session->finish();
	$session->disconnect();

	return undef;
}

1;
