package OpenILS::WWW::Method;
use strict; use warnings;

use Apache2 ();
use Apache::Log;
use Apache::Const -compile => qw(OK REDIRECT :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache::RequestRec ();
use Apache::RequestIO ();
use Apache::RequestUtil;

use JSON;

use CGI ();

use OpenSRF::EX qw(:try);
use OpenSRF::System;

my %session_hash;

use constant MAX_SESSION_REQUESTS => 20;

sub handler {

	my $apache = shift;
	my $cgi = CGI->new( $apache );

	my $method = $cgi->param("method");
	my $service = $cgi->param("service");

	my @a = $cgi->param();

	my @param_array;
	my %param_hash;

	if(defined($cgi->param("__param"))) {
		for my $param ( $cgi->param("__param")) {
			push( @param_array, JSON->JSON2perl( $param ));
		}
	} else {
		for my $param ($cgi->param()) {
			$param_hash{$param} = $cgi->param($param)
				unless( $param eq "method" or $param eq "service" );
		}
	}

	print "Content-type: text/plain; charset=utf-8\n\n";

	if( @param_array ) {
		perform_method($service, $method, @param_array);
	} else {
		perform_method($service, $method, %param_hash);
	}

	use Data::Dumper;
	warn JSON->perl2JSON( \@param_array );
	warn "===============\n";
	warn Dumper \@param_array;

	return Apache::OK;
}

sub child_init_handler {
	OpenSRF::System->bootstrap_client( 
			config_file => "/pines/conf/bootstrap.conf" );
}


sub perform_method {

	my ($service, $method, @params) = @_;

	warn "performing method $method for service $service with params @params\n";

	my $session;

	if($session_hash{$service} ) {

		$session = $session_hash{$service};
		$session->{web_count} += 1;

		if( $session->{web_count} > MAX_SESSION_REQUESTS) {
			$session->disconnect();
			$session->{web_count} = 1;
		}

	} else { 

		$session = OpenSRF::AppSession->create($service); 
		$session_hash{$service} = $session;
		$session->{web_count} = 1;

	}

	my $request = $session->request( $method, @params );

	my @results;
	while( my $response = $request->recv(20) ) {
		
		if( UNIVERSAL::isa( $response, "Error" )) {
			warn "Received exception: " . $response->stringify . "\n";
			print  JSON->perl2JSON($response->stringify);
			$request->finish();
			return 0;
		}

		my $content = $response->content;
		push @results, $content;
	}


	if(!$request->complete) { 
		warn "<b>ERROR Completing Request</b>"; 
		print JSON->perl2JSON("<b>ERROR Completing Request</b>"); 
		$request->finish();
		return 0;
	}

	$request->finish();
	$session->finish();

	print JSON->perl2JSON( \@results );

	return 1;
}


1;
