package OpenSRF::UnixServer;
use strict; use warnings;
use base qw/OpenSRF/;
use OpenSRF::EX;
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::Transport::PeerHandle;
use OpenSRF::Application;
use OpenSRF::AppSession;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::System;
use vars qw/@ISA/;
use Carp;

# XXX Need to add actual logging statements in the code
my $logger = "OpenSRF::Utils::Logger";

sub DESTROY { confess "Dying $$"; }

=head1 What am I

All inbound messages are passed on to the UnixServer for processing.
We take the data, close the Unix socket, and pass the data on to our abstract
'process()' method.  

Our purpose is to 'multiplex' a single TCP connection into multiple 'client' connections.
So when you pass data down the Unix socket to us, we have been preforked and waiting
to disperse new data among us.

=cut

{
	my $app;
	sub app { return $app; }

	sub new {
		my( $class, $app1 ) = @_;
		if( ! $app1 ) {
			throw OpenSRF::EX::InvalidArg( "UnixServer requires an app name to run" );
		}
		$app = $app1;
		my $self = bless( {}, $class );
		if( OpenSRF::Utils::Config->current->system->server_type !~ /fork/i ) {
			$self->child_init_hook();
		}
		return $self;
	}

}

=head2 process_request()

Takes the incoming data, closes the Unix socket and hands the data untouched 
to the abstract process() method.  This method is implemented in our subclasses.

=cut

sub process_request {

	my $self = shift;
	my $data; my $d;
	while( $d = <STDIN> ) { $data .= $d; }


	if( ! $data or ! defined( $data ) or $data eq "" ) {
		throw OpenSRF::EX::Socket(
				"Unix child received empty data from socket" );
	}

	if( ! close( $self->{server}->{client} ) ) {
		$logger->debug( "Error closing Unix socket: $!", ERROR );
	}


	my $app = $self->app();
	$logger->transport( "UnixServer for $app received $data", INTERNAL );

	my $app_session = OpenSRF::Transport->handler( $self->app(), $data );
	my $config = OpenSRF::Utils::Config->current;


	my $keepalive = OpenSRF::Utils::Config->current->system->keep_alive;

	my $req_counter = 0;
	while( $app_session->state and $app_session->state != $app_session->DISCONNECTED() and
			$app_session->find( $app_session->session_id ) ) {
		

		my $before = time;
		$logger->transport( "UnixServer calling queue_wait $keepalive", INTERNAL );
		$app_session->queue_wait( $keepalive );
		my $after = time;

		if( ($after - $before) >= $keepalive ) { 

			my $res = OpenSRF::DomainObject::oilsConnectStatus->new(
									status => "Disconnected on timeout",
									statusCode => STATUS_TIMEOUT);
			$app_session->status($res);
			$app_session->state( $app_session->DISCONNECTED() );
			last;
		}

	}

	my $x = 0;
	while( 1 ) {
		$logger->transport( "Looping on zombies " . $x++ , DEBUG);
		last unless ( $app_session->queue_wait(0));
	}

	$logger->transport( "Timed out, disconnected, or auth failed", INFO );
	$app_session->kill_me;
		
}


sub serve {
	my( $self ) = @_;
	my $config = OpenSRF::Utils::Config->current;
	my $app = $self->app();
	my $conf_base =  $config->dirs->conf_dir;
	my $conf = join( "/", $conf_base, $config->unix_conf->$app );
	$logger->transport( 
			"Running UnixServer as @OpenSRF::UnixServer::ISA for $app with conf file: $conf", INTERNAL );
	$self->run( 'conf_file' => $conf );
}

sub configure_hook {
	my $self = shift;
	my $app = $self->app;
	my $config = OpenSRF::Utils::Config->current;

	$logger->debug( "Setting application implementaion for $app", DEBUG );

	OpenSRF::Application->application_implementation( $config->application_implementation->$app );
	OpenSRF::Application->application_implementation->initialize()
		if (OpenSRF::Application->application_implementation->can('initialize'));
	return OpenSRF::Application->application_implementation;
}

sub child_finish_hook {
	my $self = shift;
	OpenSRF::AppSession->kill_client_session_cache;
}

sub child_init_hook { 

	my $self = shift;
	$logger->transport( 
			"Creating PeerHandle from UnixServer child_init_hook", INTERNAL );
	OpenSRF::Transport::PeerHandle->construct( $self->app() );
	my $peer_handle = OpenSRF::System::bootstrap_client("system_client");
	OpenSRF::Application->application_implementation->child_init
		if (OpenSRF::Application->application_implementation->can('child_init'));
	return $peer_handle;

}

1;

