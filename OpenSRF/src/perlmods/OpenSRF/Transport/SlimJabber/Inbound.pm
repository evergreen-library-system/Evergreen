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

			my $conf = OpenSRF::Utils::Config->current;
			my $domains = $conf->bootstrap->domains;

			my $username	= $conf->bootstrap->username;
			my $password	= $conf->bootstrap->passwd;
			my $port			= $conf->bootstrap->port;
			my $host			= $domains->[0]; # XXX for now...
			my $resource	= $app . '_listener_at_' . $conf->env->hostname;

			OpenSRF::Utils::Logger->transport("Inbound as $username, $password, $resource, $host, $port\n", INTERNAL );

			my $self = __PACKAGE__->SUPER::new( 
					username		=> $username,
					resource		=> $resource,
					password		=> $password,
					host			=> $host,
					port			=> $port,
					);

			$self->{app} = $app;
					
			my $client = OpenSRF::Utils::SettingsClient->new();
			my $f = $client->config_value("dirs", "sock");
			$unix_sock = join( "/", $f, 
					$client->config_value("apps", $app, "unix_config", "unix_sock" ));
			bless( $self, $class );
			$instance = $self;
		}
		return $instance;
	}

}

sub DESTROY {
	my $self = shift;

	my $routers = $self->{routers}; #store for destroy
	my $router_name = $self->{router_name};

	unless($router_name and $routers) {
		return;
	}

	my @targets;
	for my $router (@$routers) {
		push @targets, "$router_name\@$router/router";
	}

	for my $router (@targets) {
		if($self->tcp_connected()) {
			$self->send( to => $router, body => "registering", 
				router_command => "unregister" , router_class => $self->{app} );
		}
	}
}
	
sub listen {
	my $self = shift;
	
	my $routers;

	try {

		my $conf = OpenSRF::Utils::Config->current;
		my $router_name = $conf->bootstrap->router_name;
		my $routers = $conf->bootstrap->domains;

		$self->{routers} = $routers; #store for destroy
		$self->{router_name} = $router_name;
	
		unless($router_name and $routers) {
			throw OpenSRF::EX::Config 
				("Missing router config information 'router_name' and 'routers'");
		}
	
		my @targets;
		for my $router (@$routers) {
			push @targets, "$router_name\@$router/router";
		}

		for my $router (@targets) {
			$logger->transport( $self->{app} . " connecting to router $router", INFO ); 
			$self->send( to => $router, 
					body => "registering", router_command => "register" , router_class => $self->{app} );
		}
		$logger->transport( $self->{app} . " :routers connected", INFO ); 

		
	} catch OpenSRF::EX::Config with {
		$logger->transport( $self->{app} . ": No routers defined" , WARN ); 
		# no routers defined
	};


	
			
	$logger->transport( $self->{app} . " going into listen loop", INFO );
	while(1) {
	
		my $sock = $self->unix_sock();
		my $o = $self->process( -1 );

		if( ! defined( $o ) ) {
			throw OpenSRF::EX::Jabber( "Listen Loop failed at 'process()'" );
		}

		my $socket = IO::Socket::UNIX->new( Peer => $sock  );
		throw OpenSRF::EX::Socket( "Unable to connect to UnixServer: socket-file: $sock \n :=> $! " )
			unless ($socket->connected);
		print $socket $o;
		$socket->close;

	}

	throw OpenSRF::EX::Socket( "How did we get here?!?!" );
}

1;

