package OpenSRF::Transport::SlimJabber::Inbound;
use strict;use warnings;
use base qw/OpenSRF::Transport::SlimJabber::Client/;
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

			my $username	= $config->transport->users->$app;
			my $password	= $config->transport->auth->password;
			my $resource	= 'system';

			if (defined $config->system->router_target) {
				$resource .= '_' . $config->env->hostname . "_$$";
			}

			my $self = __PACKAGE__->SUPER::new( 
					username		=> $username,
					resource		=> $resource,
					password		=> $password,
					);

			$self->{app} = $app;
					
					
			my $f = $config->dirs->sock_dir;
			$unix_sock = join( "/", $f, $config->unix_sock->$app );
			bless( $self, $class );
			$instance = $self;
		}
		return $instance;
	}

}
	
sub listen {
	my $self = shift;
	
	my $config = OpenSRF::Utils::Config->current;
	my $routers = $config->system->router_target;
	if (defined $routers) {
		for my $router (@$routers) {
			$self->send( to => $router, 
					body => "registering", router_command => "register" , router_class => $self->{app} );
		}
	}
			
	while(1) {
		my $sock = $self->unix_sock();
		my $socket = IO::Socket::UNIX->new( Peer => $sock  );
	
		throw OpenSRF::EX::Socket( "Unable to connect to UnixServer: socket-file: $sock \n :=> $! " )
			unless ($socket->connected);

		my $o = $self->process( -1 );

		if( ! defined( $o ) ) {
			throw OpenSRF::EX::Jabber( "Listen Loop failed at 'process()'" );
		}
		print $socket $o;

		$socket->close;

	}

	throw OpenSRF::EX::Socket( "How did we get here?!?!" );
}

1;

