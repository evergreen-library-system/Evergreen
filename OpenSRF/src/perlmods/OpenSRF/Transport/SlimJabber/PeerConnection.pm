package OpenSRF::Transport::SlimJabber::PeerConnection;
use strict;
use base qw/OpenSRF::Transport::SlimJabber::Client/;
use OpenSRF::Utils::Config;
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::EX qw/:try/;

=head1 Description

Represents a single connection to a remote peer.  The 
Jabber values are loaded from the config file.  

Subclasses OpenSRF::Transport::SlimJabber::Client.

=cut

=head2 new()

	new( $appname );

	The $appname parameter tells this class how to find the correct
	Jabber username, password, etc to connect to the server.

=cut

our %apps_hash;
our $_singleton_connection;

sub retrieve { 
	my( $class, $app ) = @_;
	return $_singleton_connection;
#	my @keys = keys %apps_hash;
#OpenSRF::Utils::Logger->transport( 
#			"Requesting peer for $app and we have @keys", INFO );
#	return $apps_hash{$app};
}



# !! In here we use the bootstrap config ....
sub new {
	my( $class, $app ) = @_;

	my $peer_con = $class->retrieve;
	return $peer_con if ($peer_con and $peer_con->tcp_connected);

	my $config = OpenSRF::Utils::Config->current;

	if( ! $config ) {
		throw OpenSRF::EX::Config( "No suitable config found for PeerConnection" );
	}

	my $trans_list = $config->bootstrap->transport;
	unless( $trans_list && $trans_list->[0] ) {
		throw OpenSRF::EX::Config ("Peer Connection needs transport info");
	}

	# For now we just use the first in the list...
	my $trans		= $trans_list->[0];

	my $username;
	if( $app eq "system_client" ) {
		$username	= $config->$trans->username;
	} else {
		$username = $app;
	}



	my $password	= $config->$trans->password;
	OpenSRF::Utils::Logger->transport( "Building Peer with " .$config->$trans->password, INTERNAL );
	my $h = $config->env->hostname;
	my $resource	= $h;
	my $server		= $config->$trans->server;
	OpenSRF::Utils::Logger->transport( "Building Peer with " .$config->$trans->server, INTERNAL );
	my $port			= $config->$trans->port;
	OpenSRF::Utils::Logger->transport( "Building Peer with " .$config->$trans->port, INTERNAL );


	OpenSRF::EX::Config->throw( "JPeer could not load all necesarry values from config" )
		unless ( $username and $password and $resource and $server and $port );

	OpenSRF::Utils::Logger->transport( "Built Peer with", INTERNAL );

	my $self = __PACKAGE__->SUPER::new( 
		username		=> $username,
		resource		=> $resource,
		password		=> $password,
		host			=> $server,
		port			=> $port,
		);	
					
	bless( $self, $class );

	$self->app($app);

	$_singleton_connection = $self;
	$apps_hash{$app} = $self;

	return $_singleton_connection;
	return $apps_hash{$app};
}

sub process {
	my $self = shift;
	my $val = $self->SUPER::process(@_);
	return 0 unless $val;
	OpenSRF::Utils::Logger->transport( "Calling transport handler for ".$self->app." with: $val", INTERNAL );
	my $t;
#try {
	$t = OpenSRF::Transport->handler($self->app, $val);

#	} catch OpenSRF::EX with {
#		my $e = shift;
#		$e->throw();

#	} catch Error with { return undef; }

	return $t;
}

sub app {
	my $self = shift;
	my $app = shift;
	if( $app ) {
		OpenSRF::Utils::Logger->transport( "PEER changing app to $app: ".$self->jid, INTERNAL );
	}

	$self->{app} = $app if ($app);
	return $self->{app};
}

1;

