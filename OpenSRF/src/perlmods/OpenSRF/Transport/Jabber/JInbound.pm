package OpenSRF::Transport::Jabber::JInbound;
use strict;use warnings;
use base qw/OpenSRF::Transport::Jabber::JabberClient/;
use OpenSRF::EX;
use OpenSRF::Utils::Config;
use OpenSRF::Utils::Logger qw(:level);

my $logger = "OpenSRF::Utils::Logger";

=head1 Description

This is the jabber connection where all incoming client requests will be accepted.
This connection takes the data, passes it off to the system then returns to take
more data.  Connection params are all taken from the config file and the values
retreived are based on the $app name passed into new().

This service should be loaded at system startup.

=cut

# XXX This will be overhauled to connect as a component instead of as
# a user.  all in good time, though.

{
	my $unix_sock;
	sub unix_sock { return $unix_sock; }
	my $instance;

	sub new {
		my( $class, $app ) = @_;
		$class = ref( $class ) || $class;
		if( ! $instance ) {
			my $app_state = $app . "_inbound";
			my $config = OpenSRF::Utils::Config->current;

			if( ! $config ) {
				throw OpenSRF::EX::Jabber( "No suitable config found" );
			}

			my $host			= $config->transport->server->primary;
			my $username	= $config->transport->users->$app;
			my $password	= $config->transport->auth->password;
			my $debug		= $config->transport->llevel->$app_state;
			my $log			= $config->transport->log->$app_state;
			my $resource	= "system";


			my $self = __PACKAGE__->SUPER::new( 
					username		=> $username,
					host			=> $host,
					resource		=> $resource,
					password		=> $password,
					log_file		=> $log,
					debug			=> $debug,
					);
					
					
			my $f = $config->dirs->sock_dir;
			$unix_sock = join( "/", $f, $config->unix_sock->$app );
			bless( $self, $class );
			$instance = $self;
		}
		$instance->SetCallBacks( message => \&handle_message );
		return $instance;
	}

}
	
# ---
# All incoming messages are passed untouched to the Unix Server for processing.  The
# Unix socket is closed by the Unix Server as soon as it has received all of the
# data.  This means we can go back to accepting more incoming connection.
# -----
sub handle_message { 
	my $sid = shift;
	my $message = shift;

	my $packet = $message->GetXML();

	$logger->transport( "JInbound $$ received $packet", INTERNAL );

	# Send the packet to the unix socket for processing.
	my $sock = unix_sock();
	my $socket;
	my $x = 0;
	for( ;$x != 5; $x++ ) { #try 5 times
		if( $socket = IO::Socket::UNIX->new( Peer => $sock  ) ) {
			last;
		}
	}
	if( $x == 5 ) {
		throw OpenSRF::EX::Socket( 
			"Unable to connect to UnixServer: socket-file: $sock \n :=> $! " );
	}
	print $socket $packet;
	close( $socket );
}


1;

