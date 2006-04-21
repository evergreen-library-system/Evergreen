package OpenSRF::Transport::SlimJabber::Client;
use strict; use warnings;
use OpenSRF::EX;
use base qw( OpenSRF );
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::Utils::Config;
use Time::HiRes qw(ualarm);
use OpenSRF::Utils::Config;

use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use IO::Socket::INET;
use IO::Socket::UNIX;

=head1 Description

OpenSRF::Transport::SlimJabber::Client

Home-brewed slimmed down jabber connection agent. Supports SSL connections
with a config file options:

  transport->server->sslport # the ssl port
  transport->server->ssl  # is this ssl?

=cut

my $logger = "OpenSRF::Utils::Logger";

sub DESTROY{
	my $self = shift;
	$self->disconnect;
}

sub disconnect{
	my $self = shift;
	my $socket = $self->{_socket};
	if( $socket and $socket->connected() ) {
		print $socket "</stream:stream>";
		close( $socket );
	}
}


=head2 new()

Creates a new Client object.

debug and log_file are not required if you don't care to log the activity, 
however all other parameters are.

%params:

	username
	resource	
	password
	debug	 
	log_file

=cut

sub new {

	my( $class, %params ) = @_;

	$class = ref( $class ) || $class;

	my $port			= $params{'port'}			|| return undef;
	my $username	= $params{'username'}	|| return undef;
	my $resource	= $params{'resource'}	|| return undef;
	my $password	= $params{'password'}	|| return undef;
	my $host			= $params{'host'}			|| return undef;

	my $jid = "$username\@$host\/$resource";

	my $self = bless {} => $class;

	$self->jid( $jid );
	$self->host( $host );
	$self->port( $port );
	$self->username( $username );
	$self->resource( $resource );
	$self->password( $password );
	$self->{temp_buffer} = "";

	$logger->transport( "Creating Client instance: $host:$port, $username, $resource",
			$logger->INFO );

	return $self;
}

# clears the tmp buffer as well as the TCP buffer
sub buffer_reset { 

	my $self = shift;
	$self->{temp_buffer} = ""; 

	my $fh = $self->{_socket};
	set_nonblock( $fh );
	my $t_buf = "";
	while( sysread( $fh, $t_buf, 4096 ) ) {} 
	set_block( $fh );
}
# -------------------------------------------------

=head2 gather()

Gathers all Jabber messages sitting in the collection queue 
and hands them each to their respective callbacks.  This call
does not block (calls Process(0))

=cut

sub gather { my $self = shift; $self->process( 0 ); }

# -------------------------------------------------

=head2 listen()

Blocks and gathers incoming messages as they arrive.  Does not return
unless an error occurs.

Throws an OpenSRF::EX::JabberException if the call to Process ever fails.

=cut
sub listen {
	my $self = shift;

	my $sock = $self->unix_sock();
	my $socket = IO::Socket::UNIX->new( Peer => $sock  );
	$logger->transport( "Unix Socket opened by Listener", INTERNAL );
	
	throw OpenSRF::EX::Socket( "Unable to connect to UnixServer: socket-file: $sock \n :=> $! " )
		unless ($socket->connected);
		
	while(1) {
		my $o = $self->process( -1 );
		$logger->transport( "Call to process() in listener returned:\n $o", INTERNAL );
		if( ! defined( $o ) ) {
			throw OpenSRF::EX::Jabber( "Listen Loop failed at 'process()'" );
		}
		print $socket $o;

	}
	throw OpenSRF::EX::Socket( "How did we get here?!?!" );
}

sub set_nonblock {
	my $fh = shift;
	my	$flags = fcntl($fh, F_GETFL, 0)
		or die "Can't get flags for the socket: $!\n";

	$logger->transport( "Setting NONBLOCK: original flags: $flags", INTERNAL );

	fcntl($fh, F_SETFL, $flags | O_NONBLOCK)
		or die "Can't set flags for the socket: $!\n";

	return $flags;
}

sub reset_fl {
	my $fh = shift;
	my $flags = shift;
	$logger->transport( "Restoring BLOCK: to flags $flags", INTERNAL );
	fcntl($fh, F_SETFL, $flags) if defined $flags;
}

sub set_block {
	my $fh = shift;

	my	$flags = fcntl($fh, F_GETFL, 0)
		or die "Can't get flags for the socket: $!\n";

	$flags &= ~O_NONBLOCK;

	fcntl($fh, F_SETFL, $flags)
		or die "Can't set flags for the socket: $!\n";
}


sub timed_read {
	my ($self, $timeout) = @_;

	$logger->transport( "Temp Buffer Contained: \n". $self->{temp_buffer}, INTERNAL) if $self->{temp_buffer};
	if( $self->can( "app" ) ) {
		$logger->transport( "timed_read called for ".$self->app.", I am: ".$self->jid, INTERNAL );
	}

	# See if there is a complete message in the temp_buffer
	# that we can return
	if( $self->{temp_buffer} ) {
		my $buffer = $self->{temp_buffer};
		my $complete = 0;
		$self->{temp_buffer} = '';

		my ($tag) = ($buffer =~ /<([^\s\?\>]+)/o);
		$logger->transport("Using tag: $tag  ", INTERNAL);

		if ( $buffer =~ /^(.*?<\/$tag>)(.*)/s) {
			$buffer = $1;
			$self->{temp_buffer} = $2;
			$complete++;
			$logger->transport( "completed read with $buffer", INTERNAL );
		} elsif ( $buffer =~ /^<$tag[^>]*?\/>(.*)/) {
			$self->{temp_buffer} = $1;
			$complete++;
			$logger->transport( "completed read with $buffer", INTERNAL );
		} else {
			$self->{temp_buffer} = $buffer;
		}
				
		if( $buffer and $complete ) {
			return $buffer;
		}

	}
	############

	my $fh = $self->{_socket};

	unless( $fh and $fh->connected ) {
		throw OpenSRF::EX::Socket ("Attempted read on closed socket", ERROR );
	}

	$logger->transport( "Temp Buffer After first attempt: \n ".$self->{temp_buffer}, INTERNAL) if $self->{temp_buffer};

	my $flags;
	if (defined($timeout) && !$timeout) {
		$flags = set_nonblock( $fh );
	}

	$timeout ||= 0;
	$logger->transport( "Calling timed_read with timetout $timeout", INTERNAL );


	my $complete = 0;
	my $first_read = 1;
	my $xml = '';
	eval {
		my $tag = '';
		eval {
			no warnings;
			local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required

			# alarm needs a number greater => 1.
			my $alarm_timeout = $timeout;
			if( $alarm_timeout > 0 and $alarm_timeout < 1 ) {
				$alarm_timeout = 1;
			}
			alarm $alarm_timeout;
			do {	

				my $buffer = $self->{temp_buffer};
				$self->{temp_buffer} = '';
				#####

				my $ff =  fcntl($fh, F_GETFL, 0);
				if ($ff == ($ff | O_NONBLOCK) and $timeout > 0 ) {
					#throw OpenSRF::EX::ERROR ("File flags are set to NONBLOCK but timeout is $timeout", ERROR );
				}

				my $t_buf = "";
				my $read_size = 1024; my $f = 0;
				while( my $n = sysread( $fh, $t_buf, $read_size ) ) {

					unless( $fh->connected ) {
						OpenSRF::EX::JabberDisconnected->throw(
							"Lost jabber client in timed_read()");
					}

					$buffer .= $t_buf;
					if( $n < $read_size ) {
						#reset_fl( $fh, $f ) if $f;
						set_block( $fh );
						last;
					}
					# see if there is any more data to grab...
					$f = set_nonblock( $fh );
				}

				#sysread($fh, $buffer, 2048, length($buffer) );
				#sysread( $fh, $t_buf, 2048 );
				#$buffer .= $t_buf;

				#####
				$logger->transport(" Got [$buffer] from the socket", INTERNAL);

				if ($first_read) {
					$logger->transport(" First read Buffer\n [$buffer]", INTERNAL);
					($tag) = ($buffer =~ /<([^\s\?\>]+){1}/o);
					$first_read--;
					$logger->transport("Using tag: $tag  ", INTERNAL);
				}

				if (!$first_read && $buffer =~ /^(.*?<\/$tag>){1}(.*)/s) {
					$buffer = $1;
					$self->{temp_buffer} = $2;
					$complete++;
					$logger->transport( "completed read with $buffer", INTERNAL );
				} elsif (!$first_read && $buffer =~ /^<$tag[^>]*?\/>(.*)/) {
					$self->{temp_buffer} = $1;
					$complete++;
					$logger->transport( "completed read with $buffer", INTERNAL );
				}
				
				$xml .= $buffer;

			} while (!$complete && $xml);
			alarm(0);
		};
		alarm(0);
	};

	$logger->transport( "XML Read: $xml", INTERNAL );
	#reset_fl( $fh, $flags) if defined $flags;
	set_block( $fh ) if defined $flags;

	if ($complete) {
		return $xml;
	}
	if( $@ ) {
		return undef;
	}
	return "";
}


# -------------------------------------------------

sub tcp_connected {

	my $self = shift;
	return 1 if ($self->{_socket} and $self->{_socket}->connected);
	return 0;
}

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

sub jid {
	my( $self, $jid ) = @_;
	$self->{'oils:jid'} = $jid if $jid;
	return $self->{'oils:jid'};
}

sub port {
	my( $self, $port ) = @_;
	$self->{'oils:port'} = $port if $port;
	return $self->{'oils:port'};
}

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
	my $self = shift;
	my %params = @_;

	my $to = $params{'to'} || return undef;
	my $body = $params{'body'} || return undef;
	my $thread = $params{'thread'} || "";
	my $router_command = $params{'router_command'} || "";
	my $router_class = $params{'router_class'} || "";

	my $msg = OpenSRF::Transport::SlimJabber::MessageWrapper->new;

	$msg->setTo( $to );
	$msg->setThread( $thread ) if $thread;
	$msg->setBody( $body );
	$msg->set_router_command( $router_command );
	$msg->set_router_class( $router_class );


	$logger->transport( 
			"JabberClient Sending message to $to with thread $thread and body: \n$body", INTERNAL );

	my $soc = $self->{_socket};
	unless( $soc and $soc->connected ) {
		throw OpenSRF::EX::Jabber ("No longer connected to jabber server");
	}
	print $soc $msg->toString;

	$logger->transport( 
			"JabberClient Sent message to $to with thread $thread and body: \n$body", INTERNAL );
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

	my $jid		= $self->jid; 
	my $host	= $self->host; 
	my $port	= $self->port; 
	my $username	= $self->username;
	my $resource	= $self->resource;
	my $password	= $self->password;

	my $stream = <<"	XML";
<stream:stream to='$host' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>
	XML

	my $conf = OpenSRF::Utils::Config->current;
	my $tail = "_$$";
	if(!$conf->bootstrap->router_name && $username eq "router") {
		$tail = "";
	}

	my $auth = <<"	XML";
<iq id='123' type='set'>
<query xmlns='jabber:iq:auth'>
<username>$username</username>
<password>$password</password>
<resource>${resource}$tail</resource>
</query>
</iq>
	XML

	my $sock_type = 'IO::Socket::INET';
	
	# if port is a string, then we're connecting to a UNIX socket
	unless( $port =~ /^\d+$/ ) {
		$sock_type = 'IO::Socket::UNIX';
	}

	# --- 5 tries to connect to the jabber server
	my $socket;
	for(1..5) {
		$socket = $sock_type->new( PeerHost => $host,
					   PeerPort => $port,
					   Peer => $port,
					   Proto    => 'tcp' );
		$logger->debug( "$jid: $_ connect attempt to $host:$port");
		last if ( $socket and $socket->connected );
		$logger->warn( "$jid: Failed to connect to server...$host:$port (Try # $_)");
		sleep 3;
	}

	unless ( $socket and $socket->connected ) {
		throw OpenSRF::EX::Jabber( " Could not connect to Jabber server: $!" );
	}

	$logger->transport( "Logging into jabber as $jid " .
			"from " . ref( $self ), DEBUG );

	print $socket $stream;

	my $buffer;
	eval {
		eval {
			local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
			alarm 3;
			sysread($socket, $buffer, 4096);
			$logger->transport( "Login buffer 1: $buffer", INTERNAL );
			alarm(0);
		};
		alarm(0);
	};

	print $socket $auth;

	if( $socket and $socket->connected() ) {
		$self->{_socket} = $socket;
	} else {
		throw OpenSRF::EX::Jabber( " ** Unable to connect to Jabber server", ERROR );
	}


	$buffer = $self->timed_read(10);

	if( $buffer ) {$logger->transport( "Login buffer 2: $buffer", INTERNAL );}

	if( $buffer and $buffer =~ /type=["\']result["\']/ ) { 
		$logger->transport( " * $jid: Jabber authenticated and connected", DEBUG );
	} else {
		if( !$buffer ) { $buffer = " "; }
		$socket->close;
		throw OpenSRF::EX::Jabber( " * $jid: Unable to authenticate: $buffer", ERROR );
	}

	return $self;
}

sub construct {
	my( $class, $app ) = @_;
	$logger->transport("Constructing new Jabber connection for $app, my class $class", INTERNAL );
	$class->peer_handle( 
			$class->new( $app )->initialize() );
}

sub process {

	my( $self, $timeout ) = @_;

	$timeout ||= 0;
	undef $timeout if ( $timeout == -1 );

	unless( $self->{_socket}->connected ) {
		OpenSRF::EX::JabberDisconnected->throw( 
		  "This JabberClient instance is no longer connected to the server " . 
		  $self->username . " : " . $self->resource, ERROR );
	}

	my $val = $self->timed_read( $timeout );

	$timeout = "FOREVER" unless ( defined $timeout );
	
	if ( ! defined( $val ) ) {
		OpenSRF::EX::Jabber->throw( 
		  "Call to Client->timed_read( $timeout ) failed", ERROR );
	} elsif ( ! $val ) {
		$logger->transport( 
			"Call to Client->timed_read( $timeout ) returned 0 bytes of data", DEBUG );
	} elsif ( $val ) {
		$logger->transport( 
			"Call to Client->timed_read( $timeout ) successfully returned data", INTERNAL );
	}

	return $val;

}


# --------------------------------------------------------------
# Sets the socket to O_NONBLOCK, reads all of the data off of
# the socket, the restores the sockets flags
# Returns 1 on success, 0 if the socket isn't connected
# --------------------------------------------------------------
sub flush_socket {

	my $self = shift;
	my $socket = $self->{_socket};

	if( $socket and $socket->connected() ) {

		my $buf;
		my	$flags = fcntl($socket, F_GETFL, 0);

		fcntl($socket, F_SETFL, $flags | O_NONBLOCK);
		while( my $n = sysread( $socket, $buf, 8192 ) ) {
			$logger->debug("flush_socket dropped $n bytes of data");
		}
		fcntl($socket, F_SETFL, $flags);

		return 1;

	} else {

		return 0;
	}
}



1;
