package OpenSRF::Transport::Jabber::JabberClient;
use strict; use warnings;
use OpenSRF::EX;
use Net::Jabber qw( Client );
use base qw( OpenSRF Net::Jabber::Client );
use OpenSRF::Utils::Logger qw(:level);

=head1 Description

OpenSRF::Transport::Jabber::JabberClient

Subclasses Net::Jabber::Client and, hence, provides the same
functionality.  What it provides in addition is mainly some logging
and exception throwing on the call to 'initialize()', which sets
up the connection and authentication.

=cut

my $logger = "OpenSRF::Utils::Logger";

sub DESTROY{};


=head2 new()

Creates a new JabberClient object.  The parameters should be self explanatory.
If not, see Net::Jabber::Client for more.  

debug and log_file are not required if you don't care to log the activity, 
however all other parameters are.

%params:

	host
	username
	resource	
	password
	debug	 
	log_file

=cut

sub new {

	my( $class, %params ) = @_;

	$class = ref( $class ) || $class;

	my $host			= $params{'host'}			|| return undef;
	my $username	= $params{'username'}	|| return undef;
	my $resource	= $params{'resource'}	|| return undef;
	my $password	= $params{'password'}	|| return undef;
	my $debug		= $params{'debug'};		 
	my $log_file	= $params{'log_file'};

	my $self;

	if( $debug and $log_file ) {
		$self = Net::Jabber::Client->new( 
				debuglevel => $debug, debugfile => $log_file );
	}
	else { $self = Net::Jabber::Client->new(); }

	bless( $self, $class );

	$self->host( $host );
	$self->username( $username );
	$self->resource( $resource );
	$self->password( $password );

	$logger->transport( "Creating Jabber instance: $host, $username, $resource",
			$logger->INFO );

	$self->SetCallBacks( send => 
			sub { $logger->transport( "JabberClient in 'send' callback: @_", INTERNAL ); } );


	return $self;
}

# -------------------------------------------------

=head2 gather()

Gathers all Jabber messages sitting in the collection queue 
and hands them each to their respective callbacks.  This call
does not block (calls Process(0))

=cut

sub gather { my $self = shift; $self->Process( 0 ); }

# -------------------------------------------------

=head2 listen()

Blocks and gathers incoming messages as they arrive.  Does not return
unless an error occurs.

Throws an OpenSRF::EX::JabberException if the call to Process ever fails.

=cut
sub listen {
	my $self = shift;
	while(1) {
		my $o = $self->process( -1 );
		if( ! defined( $o ) ) {
			throw OpenSRF::EX::Jabber( "Listen Loop failed at 'Process()'" );
		}
	}
}

# -------------------------------------------------

sub password {
	my( $self, $password ) = @_;
	$self->{'oils:password'} = $password if $password;
	return $self->{'oils:password'};
}

# -------------------------------------------------

sub username {
	my( $self, $username ) = @_;
	$self->{'oils:username'} = $username if $username;
	return $self->{'oils:username'};
}
	
# -------------------------------------------------

sub resource {
	my( $self, $resource ) = @_;
	$self->{'oils:resource'} = $resource if $resource;
	return $self->{'oils:resource'};
}

# -------------------------------------------------

sub host {
	my( $self, $host ) = @_;
	$self->{'oils:host'} = $host if $host;
	return $self->{'oils:host'};
}

# -------------------------------------------------

=head2 send()

	Sends a Jabber message.
	
	%params:
		to			- The JID of the recipient
		thread	- The Jabber thread
		body		- The body of the message

=cut

sub send {
	my( $self, %params ) = @_;

	my $to = $params{'to'} || return undef;
	my $body = $params{'body'} || return undef;
	my $thread = $params{'thread'};

	my $msg = Net::Jabber::Message->new();

	$msg->SetTo( $to );
	$msg->SetThread( $thread ) if $thread;
	$msg->SetBody( $body );

	$logger->transport( 
			"JabberClient Sending message to $to with thread $thread and body: \n$body", INTERNAL );

	$self->Send( $msg );
}


=head2 inintialize()

Connect to the server and log in.  

Throws an OpenSRF::EX::JabberException if we cannot connect
to the server or if the authentication fails.

=cut

# --- The logging lines have been commented out until we decide 
# on which log files we're using.

sub initialize {

	my $self = shift;

	my $host			= $self->host; 
	my $username	= $self->username;
	my $resource	= $self->resource;
	my $password	= $self->password;

	my $jid = "$username\@$host\/$resource";

	# --- 5 tries to connect to the jabber server
	my $x = 0;
	for( ; $x != 5; $x++ ) {
		$logger->transport( "$jid: Attempting to connecto to server...$x", WARN );
		if( $self->Connect( 'hostname' => $host ) ) {
			last; 
		}
		else { sleep 3; }
	}

	if( $x == 5 ) {
		die "could not connect to server $!\n";
		throw OpenSRF::EX::Jabber( " Could not connect to Jabber server" );
	}

	$logger->transport( "Logging into jabber as $jid " .
			"from " . ref( $self ), DEBUG );

	# --- Log in
	my @a = $self->AuthSend( 'username' => $username, 
		'password' => $password, 'resource' => $resource );

	if( $a[0] eq "ok" ) { 
		$logger->transport( " * $jid: Jabber authenticated and connected", DEBUG );
	}
	else {
		throw OpenSRF::EX::Jabber( " * $jid: Unable to authenticate: @a" );
	}

	return $self;
}

sub construct {
	my( $class, $app ) = @_;
	$logger->transport("Constructing new Jabber connection for $app", INTERNAL );
	$class->peer_handle( 
			$class->new( $app )->initialize() );
}

sub process {

	my( $self, $timeout ) = @_;
	if( ! $timeout ) { $timeout = 0; }

	unless( $self->Connected() ) {
		OpenSRF::EX::Jabber->throw( 
		  "This JabberClient instance is no longer connected to the server", ERROR );
	}

	my $val;

	if( $timeout eq "-1" ) {
		$val = $self->Process();
	}
	else { $val = $self->Process( $timeout ); }

	if( $timeout eq "-1" ) { $timeout = " "; }
	
	if( ! defined( $val ) ) {
		OpenSRF::EX::Jabber->throw( 
		  "Call to Net::Jabber::Client->Process( $timeout ) failed", ERROR );
	}
	elsif( ! $val ) {
		$logger->transport( 
			"Call to Net::Jabber::Client->Process( $timeout ) returned 0 bytes of data", DEBUG );
	}
	elsif( $val ) {
		$logger->transport( 
			"Call to Net::Jabber::Client->Process( $timeout ) successfully returned data", INTERNAL );
	}

	return $val;

}


1;
