package OpenSRF::Transport::Jabber::JPeerConnection;
use strict;
use base qw/OpenSRF::Transport::Jabber::JabberClient/;
use OpenSRF::Utils::Config;
use OpenSRF::Utils::Logger qw(:level);

=head1 Description

Represents a single connection to a remote peer.  The 
Jabber values are loaded from the config file.  

Subclasses OpenSRF::Transport::JabberClient.

=cut

=head2 new()

	new( $appname );

	The $appname parameter tells this class how to find the correct
	Jabber username, password, etc to connect to the server.

=cut

our $main_instance;
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
	my $host			= $config->transport->server->primary;
	my $username	= $config->transport->users->$app;
	my $password	= $config->transport->auth->password;
	my $debug		= $config->transport->llevel->$app_stat;
	my $log			= $config->transport->log->$app_stat;
	my $resource	= $config->env->hostname . "_$$";

	OpenSRF::EX::Config->throw( "JPeer could not load all necesarry values from config" )
		unless ( $host and $username and $password and $resource );


	my $self = __PACKAGE__->SUPER::new( 
		username		=> $username,
		host			=> $host,
		resource		=> $resource,
		password		=> $password,
		log_file		=> $log,
		debug			=> $debug,
		);	
					
	 bless( $self, $class );

	 $self->SetCallBacks( message => sub {
			 my $msg = $_[1];
			 OpenSRF::Utils::Logger->transport( 
				 "JPeer passing \n$msg \n to Transport->handler for $app", INTERNAL );
			 OpenSRF::Transport->handler( $app, $msg ); } );

	$apps_hash{$app} = $self;
	return $apps_hash{$app};
}
	
1;

