package OpenSRF::Transport::SlimJabber::Inbound;
use strict;use warnings;
use base qw/OpenSRF::Transport::SlimJabber::Client/;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Config;

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

			my $client = OpenSRF::Utils::SettingsClient->new();

			my $transport_info = $client->config_value(
					"apps", $app, "transport_hosts", "transport_host" );

			if( !ref($transport_info) eq "ARRAY" ) {
				$transport_info = [$transport_info];
			}


			# XXX for now, we just try the first host...

			my $username = $transport_info->[0]->{username};
			my $password	= $transport_info->[0]->{password};
			my $resource	= 'system';
			my $host			= $transport_info->[0]->{host};
			my $port			= $transport_info->[0]->{port};

			if (defined $client->config_value("router_targets")) {
				my $h = OpenSRF::Utils::Config->current->env->hostname;
				$resource .= "_$h";
			}

			OpenSRF::Utils::Logger->transport("Inbound as $username, $password, $resource, $host, $port\n", INTERNAL );

			my $self = __PACKAGE__->SUPER::new( 
					username		=> $username,
					resource		=> $resource,
					password		=> $password,
					host			=> $host,
					port			=> $port,
					);

			$self->{app} = $app;
					
			my $f = $client->config_value("dirs", "sock");
			$unix_sock = join( "/", $f, 
					$client->config_value("apps", $app, "unix_config", "unix_sock" ));
			bless( $self, $class );
			$instance = $self;
		}
		return $instance;
	}

}
	
sub listen {
	my $self = shift;
	
	my $client = OpenSRF::Utils::SettingsClient->new();
	my $routers;
	try {

		$routers = $client->config_value("router_targets","router_target");
		$logger->transport( $self->{app} . " connecting to router $routers", INFO ); 

		if (defined $routers) {
			if( !ref($routers) || !(ref($routers) eq "ARRAY") ) {
				$routers = [$routers];
			}


			for my $router (@$routers) {
				$logger->transport( $self->{app} . " connecting to router $router", INFO ); 
				$self->send( to => $router, 
						body => "registering", router_command => "register" , router_class => $self->{app} );
			}
			$logger->transport( $self->{app} . " :routers connected", INFO ); 

		}
	} catch OpenSRF::EX::Config with {
		$logger->transport( $self->{app} . ": No routers defined" , WARN ); 
		# no routers defined
	};


	
			
	$logger->transport( $self->{app} . " going into listen loop", INFO );
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

