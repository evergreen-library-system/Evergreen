package OpenSRF::AppSession;
use OpenSRF::DOM;
#use OpenSRF::DOM::Element::userAuth;
use OpenSRF::DomainObject::oilsMessage;
use OpenSRF::DomainObject::oilsMethod;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::Transport::PeerHandle;
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Config;
use OpenSRF::EX;
use OpenSRF;
use Exporter;
use base qw/Exporter OpenSRF/;
use Time::HiRes qw( time usleep );
use warnings;
use strict;

our @EXPORT_OK = qw/CONNECTING INIT_CONNECTED CONNECTED DISCONNECTED CLIENT SERVER/;
our %EXPORT_TAGS = ( state => [ qw/CONNECTING INIT_CONNECTED CONNECTED DISCONNECTED/ ],
		 endpoint => [ qw/CLIENT SERVER/ ],
);

my $logger = "OpenSRF::Utils::Logger";

our %_CACHE;
our @_CLIENT_CACHE;
our @_RESEND_QUEUE;

sub kill_client_session_cache {
	for my $session ( @_CLIENT_CACHE ) {
		$session->kill_me;
	}
}

sub CONNECTING { return 3 };
sub INIT_CONNECTED { return 4 };
sub CONNECTED { return 1 };
sub DISCONNECTED { return 2 };

sub CLIENT { return 2 };
sub SERVER { return 1 };

sub find {
	return undef unless (defined $_[1]);
	return $_CACHE{$_[1]} if (exists($_CACHE{$_[1]}));
}

sub find_client {
	my( $self, $app ) = @_;
	$logger->debug( "Client Cache contains: " .scalar(@_CLIENT_CACHE), INTERNAL );
	my ($client) = grep { $_->[0] eq $app and $_->[1] == 1 } @_CLIENT_CACHE;
	$client->[1] = 0;
	return $client->[2];
}

sub transport_connected {
	my $self = shift;
	if( ! exists $self->{peer_handle} || ! $self->{peer_handle} ) {
		return 0;
	}
	return $self->{peer_handle}->tcp_connected();
}

# ----------------------------------------------------------------------------
# Clears the transport buffers
# call this if you are not through with the sesssion, but you want 
# to have a clean slate.  You shouldn't have to call this if
# you are correctly 'recv'ing all of the data from a request.
# however, if you don't want all of the data, this will
# slough off any excess
#  * * Note: This will delete data for all sessions using this transport
# handle.  For example, all client sessions use the same handle.
# ----------------------------------------------------------------------------
sub buffer_reset {

	my $self = shift;
	if( ! exists $self->{peer_handle} || ! $self->{peer_handle} ) { 
		return 0;
	}
	$self->{peer_handle}->buffer_reset();
}


sub client_cache {
	my $self = shift;
	push @_CLIENT_CACHE, [ $self->app, 1, $self ];
}

# when any incoming data is received, this method is called.
sub server_build {
	my $class = shift;
	$class = ref($class) || $class;

	my $sess_id = shift;
	my $remote_id = shift;
	my $service = shift;

	return undef unless ($sess_id and $remote_id and $service);

	my $config_client = OpenSRF::Utils::SettingsClient->new();
	
	if ( my $thingy = $class->find($sess_id) ) {
		$thingy->remote_id( $remote_id );
		$logger->debug( "AppSession returning existing session $sess_id", DEBUG );
		return $thingy;
	} else {
		$logger->debug( "AppSession building new server session $sess_id", DEBUG );
	}

	if( $service eq "client" ) {
		#throw OpenSRF::EX::PANIC ("Attempting to build a client session as a server" .
		#	" Session ID [$sess_id], remote_id [$remote_id]");
		$logger->debug("Attempting to build a client session as ".
				"a server Session ID [$sess_id], remote_id [$remote_id]", ERROR );
	}


	#my $max_requests = $conf->$service->max_requests;
	my $max_requests	= $config_client->config_value("apps",$service,"max_requests");
	$logger->debug( "Max Requests for $service is $max_requests", INTERNAL );# if $max_requests;

	$logger->transport( "AppSession creating new session: $sess_id", INTERNAL );

	my $self = bless { recv_queue  => [],
			   request_queue  => [],
			   requests  => 0,
			   session_data  => {},
			   callbacks  => { death => [], disconnect => [] },
			   endpoint    => SERVER,
			   state       => CONNECTING, 
			   session_id  => $sess_id,
			   remote_id	=> $remote_id,
				peer_handle => OpenSRF::Transport::PeerHandle->retrieve($service),
				max_requests => $max_requests,
				session_threadTrace => 0,
				service => $service,
			 } => $class;

	return $_CACHE{$sess_id} = $self;
}

sub session_data {
	my $self = shift;
	my ($name, $datum) = @_;

	$self->{session_data}->{$name} = $datum if (defined $datum);
	return $self->{session_data}->{$name};
}

sub service { return shift()->{service}; }

sub continue_request {
	my $self = shift;
	$self->{'requests'}++;
	return 1 if (!$self->{'max_requests'});
	return $self->{'requests'} <= $self->{'max_requests'} ? 1 : 0;
}

sub last_sent_payload {
	my( $self, $payload ) = @_;
	if( $payload ) {
		return $self->{'last_sent_payload'} = $payload;
	}
	return $self->{'last_sent_payload'};
}

sub last_sent_type {
	my( $self, $type ) = @_;
	if( $type ) {
		return $self->{'last_sent_type'} = $type;
	}
	return $self->{'last_sent_type'};
}

sub get_app_targets {
	my $app = shift;

#	my $config_client = OpenSRF::Utils::SettingsClient->new();

	my $conf = OpenSRF::Utils::Config->current;
	my $router_name = $conf->bootstrap->router_name;
	my $routers = $conf->bootstrap->domains;

	unless($router_name and $routers) {
		throw OpenSRF::EX::Config 
			("Missing router config information 'router_name' and 'routers'");
	}

	my @targets;
	for my $router (@$routers) {
		push @targets, "$router_name\@$router/$app";
	}

	return @targets;
}

# When we're a client and we want to connect to a remote service
# create( $app, username => $user, secret => $passwd );
#    OR
# create( $app, sysname => $user, secret => $shared_secret );
sub create {
	my $class = shift;
	$class = ref($class) || $class;

	my $app = shift;

	if( my $thingy = OpenSRF::AppSession->find_client( $app ) ) {
			$logger->debug( "AppSession returning existing client session for $app", DEBUG );
			return $thingy;
	} else {
		$logger->debug( "AppSession creating new client session for $app", DEBUG );
	}


	my $sess_id = time . rand( $$ );
	while ( $class->find($sess_id) ) {
		$sess_id = time . rand( $$ );
	}

	my ($r_id) = get_app_targets($app);

	my $peer_handle = OpenSRF::Transport::PeerHandle->retrieve("client"); 
	if( ! $peer_handle ) {
		$peer_handle = OpenSRF::Transport::PeerHandle->retrieve("system_client");
	}

	my $self = bless { app_name    => $app,
				#client_auth => $auth,
			   #recv_queue  => [],
			   request_queue  => [],
			   endpoint    => CLIENT,
			   state       => DISCONNECTED,#since we're init'ing
			   session_id  => $sess_id,
			   remote_id   => $r_id,
			   api_level   => 1,
			   orig_remote_id   => $r_id,
				peer_handle => $peer_handle,
				session_threadTrace => 0,
			 } => $class;

	$self->client_cache();
	$_CACHE{$sess_id} = $self;
	return $self->find_client( $app );
}

sub api_level {
	return shift()->{api_level};
}

sub app {
	return shift()->{app_name};
}

sub reset {
	my $self = shift;
	$self->remote_id($$self{orig_remote_id});
}

# 'connect' can be used as a constructor if called as a class method,
# or used to connect a session that has disconnectd if called against
# an existing session that seems to be disconnected, or was just built
# using 'create' above.

# connect( $app, username => $user, secret => $passwd );
#    OR
# connect( $app, sysname => $user, secret => $shared_secret );

# --- Returns undef if the connect attempt times out.
# --- Returns the OpenSRF::EX object if one is returned by the server
# --- Returns self if connected
sub connect {
	my $self = shift;
	my $class = ref($self) || $self;

	if ( ref( $self ) and  $self->state && $self->state == CONNECTED  ) {
		$logger->transport("ABC AppSession already connected", DEBUG );
	} else {
		$logger->transport("ABC AppSession not connected, connecting..", DEBUG );
	}
	return $self if ( ref( $self ) and  $self->state && $self->state == CONNECTED  );

	my $app = shift;
	my $api_level = shift;
	$api_level = 1 unless (defined $api_level);

	$self = $class->create($app, @_) if (!ref($self));
	return undef unless ($self);

	$self->{api_level} = $api_level;

	$self->reset;
	$self->state(CONNECTING);
	$self->send('CONNECT', "");

	# if we want to connect to settings, we may not have 
	# any data for the settings client to work with...
	# just using a default for now XXX

	my $time_remaining = 5;
	
=head blah
	my $client = OpenSRF::Utils::SettingsClient->new();
	my $trans = $client->config_value("client_connection","transport_host");

	if(!ref($trans)) {
		$time_remaining = $trans->{connect_timeout};
	} else {
		# XXX for now, just use the first
		$time_remaining = $trans->[0]->{connect_timeout};
	}
=cut

	while ( $self->state != CONNECTED  and $time_remaining > 0 ) {
		my $starttime = time;
		$self->queue_wait($time_remaining);
		my $endtime = time;
		$time_remaining -= ($endtime - $starttime);
	}

	return undef unless($self->state == CONNECTED);

	return $self;
}

sub finish {
	my $self = shift;
	if( ! $self->session_id ) {
		return 0;
	}
	#$self->disconnect if ($self->endpoint == CLIENT);
	for my $ses ( @_CLIENT_CACHE ) {
		if ($ses->[2]->session_id eq $self->session_id) {
			$ses->[1] = 1;
		}
	}
}

sub register_callback {
	my $self = shift;
	my $type = shift;
	my $cb = shift;
	push @{ $self->{callbacks}{$type} }, $cb;
}

sub kill_me {
	my $self = shift;
	if( ! $self->session_id ) { return 0; }

	# run each 'kill_me' callback;
	for my $sub (@{$self->{callbacks}{death}}) {
		$sub->($self);
	}

	$self->disconnect;
	$logger->transport( "AppSession killing self: " . $self->session_id(), DEBUG );
	my @a;
	for my $ses ( @_CLIENT_CACHE ) {
		push @a, $ses 
			if ($ses->[2]->session_id ne $self->session_id);
	}
	@_CLIENT_CACHE = @a;
	delete $_CACHE{$self->session_id};
	delete($$self{$_}) for (keys %$self);
}

sub disconnect {
	my $self = shift;
	unless( $self->state == DISCONNECTED ) {
		$self->send('DISCONNECT', "") if ($self->endpoint == CLIENT);;
		$self->state( DISCONNECTED ); 
	}
	# run each 'disconnect' callback;
	for my $sub (@{$self->{callbacks}{disconnect}}) {
		$sub->($self);
	}

	$self->reset;
}

sub request {
	my $self = shift;
	my $meth = shift;

	my $method;
	if (!ref $meth) {
		$method = new OpenSRF::DomainObject::oilsMethod ( method => $meth );
	} else {
		$method = $meth;
	}
	
	$method->params( @_ );

	$self->send('REQUEST',$method);
}


sub send {
	my $self = shift;
	my @payload_list = @_; # this is a Domain Object


	$logger->debug( "In send", INTERNAL );
	
	my $tT;

	if( @payload_list % 2 ) { $tT = pop @payload_list; }

	if( ! @payload_list ) {
		$logger->debug( "payload_list param is incomplete in AppSession::send()", ERROR );
		return undef; 
	}

	my $doc = OpenSRF::DOM->createDocument();

	$logger->debug( "In send2", INTERNAL );

	my $disconnect = 0;
	my $connecting = 0;

	while( @payload_list ) {

		my ($msg_type, $payload) = ( shift(@payload_list), shift(@payload_list) ); 

		if ($msg_type eq 'DISCONNECT' ) {
			$disconnect++;
			if( $self->state == DISCONNECTED) {
				next;
			}
		}

		if( $msg_type eq "CONNECT" ) { $connecting++; }


		if( $payload ) {
			$logger->debug( "Payload is ".$payload->toString, INTERNAL );
		}
	
	
		my $msg = OpenSRF::DomainObject::oilsMessage->new();
		$logger->debug( "AppSession after creating oilsMessage $msg", INTERNAL );
		
		$msg->type($msg_type);
		$logger->debug( "AppSession after adding type" . $msg->toString(), INTERNAL );
	
		#$msg->userAuth($self->client_auth) if ($self->endpoint == CLIENT && $msg_type eq 'CONNECT');
	
		no warnings;
		$msg->threadTrace( $tT || int($self->session_threadTrace) || int($self->last_threadTrace) );
		use warnings;
	
		if ($msg->type eq 'REQUEST') {
			if ( !defined($tT) || $self->last_threadTrace != $tT ) {
				$msg->update_threadTrace;
				$self->session_threadTrace( $msg->threadTrace );
				$tT = $self->session_threadTrace;
				OpenSRF::AppRequest->new($self, $payload);
			}
		}
	
		$msg->api_level($self->api_level);
		$msg->payload($payload) if $payload;
	
		$doc->documentElement->appendChild( $msg );

	
		$logger->debug( "AppSession sending ".$msg->type." to ".$self->remote_id.
			" with threadTrace [".$msg->threadTrace."]", INFO );

	}
	
	if ($self->endpoint == CLIENT and ! $disconnect) {
		$self->queue_wait(0);
		unless ($self->state == CONNECTED || ($self->state == CONNECTING && $connecting )) {
			my $v = $self->connect();
			if( ! $v ) {
				$logger->debug( "Unable to connect to remote service in AppSession::send()", ERROR );
				return undef;
			}
			if( ref($v) and $v->can("class") and $v->class->isa( "OpenSRF::EX" ) ) {
				return $v;
			}
		}
	} 

	$logger->debug( "AppSession sending doc: " . $doc->toString(), INTERNAL );


	$self->{peer_handle}->send( 
					to     => $self->remote_id,
				   thread => $self->session_id,
				   body   => $doc->toString );

	return $self->app_request( $tT );
}

sub app_request {
	my $self = shift;
	my $tT = shift;
	
	return undef unless (defined $tT);
	my ($req) = grep { $_->threadTrace == $tT } @{ $self->{request_queue} };

	return $req;
}

sub remove_app_request {
	my $self = shift;
	my $req = shift;
	
	my @list = grep { $_->threadTrace != $req->threadTrace } @{ $self->{request_queue} };

	$self->{request_queue} = \@list;
}

sub endpoint {
	return $_[0]->{endpoint};
}


sub session_id {
	my $self = shift;
	return $self->{session_id};
}

sub push_queue {
	my $self = shift;
	my $resp = shift;
	my $req = $self->app_request($resp->[1]);
	return $req->push_queue( $resp->[0] ) if ($req);
	push @{ $self->{recv_queue} }, $resp->[0];
}

sub last_threadTrace {
	my $self = shift;
	my $new_last_threadTrace = shift;

	my $old_last_threadTrace = $self->{last_threadTrace};
	if (defined $new_last_threadTrace) {
		$self->{last_threadTrace} = $new_last_threadTrace;
		return $new_last_threadTrace unless ($old_last_threadTrace);
	}

	return $old_last_threadTrace;
}

sub session_threadTrace {
	my $self = shift;
	my $new_last_threadTrace = shift;

	my $old_last_threadTrace = $self->{session_threadTrace};
	if (defined $new_last_threadTrace) {
		$self->{session_threadTrace} = $new_last_threadTrace;
		return $new_last_threadTrace unless ($old_last_threadTrace);
	}

	return $old_last_threadTrace;
}

sub last_message_type {
	my $self = shift;
	my $new_last_message_type = shift;

	my $old_last_message_type = $self->{last_message_type};
	if (defined $new_last_message_type) {
		$self->{last_message_type} = $new_last_message_type;
		return $new_last_message_type unless ($old_last_message_type);
	}

	return $old_last_message_type;
}

sub last_message_api_level {
	my $self = shift;
	my $new_last_message_api_level = shift;

	my $old_last_message_api_level = $self->{last_message_api_level};
	if (defined $new_last_message_api_level) {
		$self->{last_message_api_level} = $new_last_message_api_level;
		return $new_last_message_api_level unless ($old_last_message_api_level);
	}

	return $old_last_message_api_level;
}

sub remote_id {
	my $self = shift;
	my $new_remote_id = shift;

	my $old_remote_id = $self->{remote_id};
	if (defined $new_remote_id) {
		$self->{remote_id} = $new_remote_id;
		return $new_remote_id unless ($old_remote_id);
	}

	return $old_remote_id;
}

sub client_auth {
	return undef;
	my $self = shift;
	my $new_ua = shift;

	my $old_ua = $self->{client_auth};
	if (defined $new_ua) {
		$self->{client_auth} = $new_ua;
		return $new_ua unless ($old_ua);
	}

	return $old_ua->cloneNode(1);
}

sub state {
	my $self = shift;
	my $new_state = shift;

	my $old_state = $self->{state};
	if (defined $new_state) {
		$self->{state} = $new_state;
		return $new_state unless ($old_state);
	}

	return $old_state;
}

sub DESTROY {
	my $self = shift;
	delete $$self{$_} for keys %$self;
	return undef;
}

sub recv {
	my $self = shift;
	my @proto_args = @_;
	my %args;

	if ( @proto_args ) {
		if ( !(@proto_args % 2) ) {
			%args = @proto_args;
		} elsif (@proto_args == 1) {
			%args = ( timeout => @proto_args );
		}
	}

	#$logger->debug( ref($self). " recv_queue before wait: " . $self->_print_queue(), INTERNAL );

	if( exists( $args{timeout} ) ) {
		$args{timeout} = int($args{timeout});
	} else {
		$args{timeout} = 10;
	}

	#$args{timeout} = 0 if ($self->complete);

	$logger->debug( ref($self) ."->recv with timeout " . $args{timeout}, INTERNAL );

	$args{count} ||= 1;

	my $avail = @{ $self->{recv_queue} };
	my $time_remaining = $args{timeout};

	while ( $avail < $args{count} and $time_remaining > 0 ) {
		last if $self->complete;
		my $starttime = time;
		$self->queue_wait($time_remaining);
		my $endtime = time;
		$time_remaining -= ($endtime - $starttime);
		$avail = @{ $self->{recv_queue} };
	}

	#$logger->debug( ref($self)." queue after wait: " . $self->_print_queue(), INTERNAL );
		
	my @list;
	while ( my $msg = shift @{ $self->{recv_queue} } ) {
		push @list, $msg;
		last if (scalar(@list) >= $args{count});
	}

#	$self->{recv_queue} = [@unlist, @{ $self->{recv_queue} }];
	$logger->debug( "Number of matched responses: " . @list, DEBUG );

	$self->queue_wait(0); # check for statuses
	
	return $list[0] unless (wantarray);
	return @list;
}

sub push_resend {
	my $self = shift;
	push @OpenSRF::AppSession::_RESEND_QUEUE, @_;
}

sub flush_resend {
	my $self = shift;
	$logger->debug( "Resending..." . @_RESEND_QUEUE, DEBUG );
	while ( my $req = shift @OpenSRF::AppSession::_RESEND_QUEUE ) {
		$req->resend;
	}
}


sub queue_wait {
	my $self = shift;
	if( ! $self->{peer_handle} ) { return 0; }
	my $timeout = shift || 0;
	$logger->debug( "Calling queue_wait($timeout)" , DEBUG );
	$logger->debug( "Timestamp before process($timeout) : " . $logger->format_time(), INTERNAL );
	my $o = $self->{peer_handle}->process($timeout);
	$logger->debug( "Timestamp after  process($timeout) : " . $logger->format_time(), INTERNAL );
	$self->flush_resend;
	return $o;
}

sub _print_queue {
	my( $self ) = @_;
	my $string = "";
	foreach my $msg ( @{$self->{recv_queue}} ) {
		$string = $string . $msg->toString(1) . "\n";
	}
	return $string;
}

sub status {
	my $self = shift;
	$self->send( 'STATUS', @_ );
}

#-------------------------------------------------------------------------------

package OpenSRF::AppRequest;
use base qw/OpenSRF::AppSession/;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::DomainObject::oilsResponse qw/:status/;

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	my $session = shift;
	my $threadTrace = $session->session_threadTrace || $session->last_threadTrace;
	my $payload = shift;
	
	my $self = {	session	    => $session,
			threadTrace => $threadTrace,
			payload	    => $payload,
			complete    => 0,
			recv_queue  => [],
	};

	bless $self => $class;

	push @{ $self->session->{request_queue} }, $self;

	return $self;
}

sub queue_size {
	my $size = @{$_[0]->{recv_queue}};
	return $size;
}
	
sub send {
	shift()->session->send(@_);
}

sub finish {
	my $self = shift;
	$self->session->remove_app_request($self);
	delete($$self{$_}) for (keys %$self);
}

sub session {
	return shift()->{session};
}

sub complete {
	my $self = shift;
	my $complete = shift;
	return $self->{complete} if ($self->{complete});
	if (defined $complete) {
		$self->{complete} = $complete;
	} else {
		$self->session->queue_wait(0);
	}
	return $self->{complete};
}

sub wait_complete {
	my $self = shift;
	my $timeout = shift || 1;
	my $time_remaining = $timeout;

	while ( ! $self->complete  and $time_remaining > 0 ) {
		my $starttime = time;
		$self->queue_wait($time_remaining);
		my $endtime = time;
		$time_remaining -= ($endtime - $starttime);
	}

	return $self->complete;
}

sub threadTrace {
	return shift()->{threadTrace};
}

sub push_queue {
	my $self = shift;
	my $resp = shift;
	if( !$resp ) { return 0; }
	push @{ $self->{recv_queue} }, $resp;
	OpenSRF::Utils::Logger->debug( "AppRequest pushed ".$resp->toString(), INTERNAL );
}

sub queue_wait {
	my $self = shift;
	OpenSRF::Utils::Logger->debug( "Calling queue_wait(@_)", DEBUG );
	return $self->session->queue_wait(@_)
}

sub payload { return shift()->{payload}; }

sub resend {
	my $self = shift;
	OpenSRF::Utils::Logger->debug(
		"I'm resending the request for threadTrace ". $self->threadTrace, DEBUG);
	if($self->payload) {
		OpenSRF::Utils::Logger->debug($self->payload->toString,INTERNAL);
	}
	return $self->session->send('REQUEST', $self->payload, $self->threadTrace );
}

sub status {
	my $self = shift;
	my $msg = shift;
	$self->session->send( 'STATUS',$msg, $self->threadTrace );
}

sub respond {
	my $self = shift;
	my $msg = shift;

	my $response;
	if (ref($msg) && UNIVERSAL::can($msg, 'getAttribute') && $msg->getAttribute('name') =~ /oilsResult/) {
		$response = $msg;
	} else {
		$response = new OpenSRF::DomainObject::oilsResult;
		$response->content($msg);
	}

	$self->session->send('RESULT', $response, $self->threadTrace);
}

sub respond_complete {
	my $self = shift;
	my $msg = shift;

	my $response;
	if (ref($msg) && UNIVERSAL::can($msg, 'getAttribute') && $msg->getAttribute('name') =~ /oilsResult/) {
		$response = $msg;
	} else {
		$response = new OpenSRF::DomainObject::oilsResult;
		$response->content($msg);
	}

	my $stat = OpenSRF::DomainObject::oilsConnectStatus->new(
		statusCode => STATUS_COMPLETE(),
		status => 'Request Complete' );

	$self->session->send( 'RESULT' => $response, 'STATUS' => $stat, $self->threadTrace);

}

sub register_death_callback {
	my $self = shift;
	my $cb = shift;
	$self->session->register_callback( death => $cb );
}

package OpenSRF::AppSubrequest;

sub respond {
	my $self = shift;
	my $resp = shift;
	push @{$$self{resp}}, $resp;
}

sub new {
	return bless({resp => []}, 'OpenSRF::AppSubrequest');
}

sub responses { @{$_[0]->{resp}} }

sub status {}


1;

