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

sub retrieve { 
	my( $class, $app ) = @_;
	my @keys = keys %apps_hash;
	OpenSRF::Utils::Logger->transport( 
			"Requesting peer for $app and we have @keys", INTERNAL );
	return $apps_hash{$app};
}



sub new {
	my( $class, $app ) = @_;
	my $config = OpenSRF::Utils::Config->current;

	if( ! $config ) {
		throw OpenSRF::EX::Config( "No suitable config found" );
	}

	my $app_stat	= $app . "_peer";
	my $username	= $config->transport->users->$app;
	my $password	= $config->transport->auth->password;
	my $resource	= $config->env->hostname . "_$$";

	OpenSRF::EX::Config->throw( "JPeer could not load all necesarry values from config" )
		unless ( $username and $password and $resource );


	my $self = __PACKAGE__->SUPER::new( 
		username		=> $username,
		resource		=> $resource,
		password		=> $password,
		);	
					
	bless( $self, $class );

	$self->app($app);

	$apps_hash{$app} = $self;
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

