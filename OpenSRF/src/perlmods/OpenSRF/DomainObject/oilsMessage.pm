package OpenSRF::DomainObject::oilsMessage;
use JSON;
use OpenSRF::AppSession;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::Utils::Logger qw/:level/;
use warnings; use strict;
use OpenSRF::EX qw/:try/;

JSON->register_class_hint(hint => 'osrfMessage', name => 'OpenSRF::DomainObject::oilsMessage', type => 'hash');

sub toString {
	my $self = shift;
	my $pretty = shift;
	return JSON->perl2prettyJSON($self) if ($pretty);
	return JSON->perl2JSON($self);
}

sub new {
	my $self = shift;
	my $class = ref($self) || $self;
	my %args = @_;
	return bless \%args => $class;
}


=head1 NAME

OpenSRF::DomainObject::oilsMessage

=head1

use OpenSRF::DomainObject::oilsMessage;

my $msg = OpenSRF::DomainObject::oilsMessage->new( type => 'CONNECT' );

$msg->payload( $domain_object );

=head1 ABSTRACT

OpenSRF::DomainObject::oilsMessage is used internally to wrap data sent
between client and server.  It provides the structure needed to authenticate
session data, and also provides the logic needed to unwrap session data and 
pass this information along to the Application Layer.

=cut

my $log = 'OpenSRF::Utils::Logger';

=head1 METHODS

=head2 OpenSRF::DomainObject::oilsMessage->type( [$new_type] )

=over 4

Used to specify the type of message.  One of
B<CONNECT, REQUEST, RESULT, STATUS, ERROR, or DISCONNECT>.

=back

=cut

sub type {
	my $self = shift;
	my $val = shift;
	$self->{type} = $val if (defined $val);
	return $self->{type};
}

=head2 OpenSRF::DomainObject::oilsMessage->api_level( [$new_api_level] )

=over 4

Used to specify the api_level of message.  Currently, only api_level C<1> is
supported.  This will be used to check that messages are well-formed, and as
a hint to the Application as to which version of a method should fulfill a
REQUEST message.

=back

=cut

sub api_level {
	my $self = shift;
	my $val = shift;
	$self->{api_level} = $val if (defined $val);
	return $self->{api_level};
}

=head2 OpenSRF::DomainObject::oilsMessage->threadTrace( [$new_threadTrace] );

=over 4

Sets or gets the current message sequence identifier, or thread trace number,
for a message.  Useful as a debugging aid, but that's about it.

=back

=cut

sub threadTrace {
	my $self = shift;
	my $val = shift;
	$self->{threadTrace} = $val if (defined $val);
	return $self->{threadTrace};
}

=head2 OpenSRF::DomainObject::oilsMessage->update_threadTrace

=over 4

Increments the threadTrace component of a message.  This is automatic when
using the normal session processing stack.

=back

=cut

sub update_threadTrace {
	my $self = shift;
	my $tT = $self->threadTrace;

	$tT ||= 0;
	$tT++;

	$log->debug("Setting threadTrace to $tT",DEBUG);

	$self->threadTrace($tT);

	return $tT;
}

=head2 OpenSRF::DomainObject::oilsMessage->payload( [$new_payload] )

=over 4

Sets or gets the payload of a message.  This should be exactly one object
of (sub)type domainObject or domainObjectCollection.

=back

=cut

sub payload {
	my $self = shift;
	my $val = shift;
	$self->{payload} = $val if (defined $val);
	return $self->{payload};
}

=head2 OpenSRF::DomainObject::oilsMessage->handler( $session_id )

=over 4

Used by the message processing stack to set session state information from the current
message, and then sends control (via the payload) to the Application layer.

=back

=cut

sub handler {
	my $self = shift;
	my $session = shift;

	my $mtype = $self->type;
	my $api_level = $self->api_level || 1;;
	my $tT = $self->threadTrace;

	$session->last_message_type($mtype);
	$session->last_message_api_level($api_level);
	$session->last_threadTrace($tT);

	$log->debug(" Received api_level => [$api_level], MType => [$mtype], ".
			"from [".$session->remote_id."], threadTrace[".$self->threadTrace."]");
	$log->debug("endpoint => [".$session->endpoint."]", DEBUG);
	$log->debug("OpenSRF::AppSession->SERVER => [".$session->SERVER()."]", DEBUG);


	my $val;
	if ( $session->endpoint == $session->SERVER() ) {
		$val = $self->do_server( $session, $mtype, $api_level, $tT );

	} elsif ($session->endpoint == $session->CLIENT()) {
		$val = $self->do_client( $session, $mtype, $api_level, $tT );
	}

	if( $val ) {
		$log->debug("Passing request up to OpenSRF::Application", DEBUG);
		return OpenSRF::Application->handler($session, $self->payload);
	} else {
		$log->debug("Request was handled internally", DEBUG);
	}

	return 1;

}



# handle server side message processing

# !!! Returning 0 means that we don't want to pass ourselves up to the message layer !!!
sub do_server {
	my( $self, $session, $mtype, $api_level, $tT ) = @_;

	# A Server should never receive STATUS messages.  If so, we drop them.
	# This is to keep STATUS's from dead client sessions from creating new server
	# sessions which send mangled session exceptions to backends for messages 
	# that they are not aware of any more.
	if( $mtype eq 'STATUS' ) { return 0; }

	
	if ($mtype eq 'DISCONNECT') {
		$session->disconnect;
		$session->kill_me;
		return 0;
	}

	if ($session->state == $session->CONNECTING()) {

		if($mtype ne "CONNECT" and $session->stateless) {
			$log->debug("Got message Stateless", DEBUG);
			return 1; #pass the message up the stack
		}

		# the transport layer thinks this is a new connection. is it?
		unless ($mtype eq 'CONNECT') {
			$log->error("Connection seems to be mangled: Got $mtype instead of CONNECT");

			my $res = OpenSRF::DomainObject::oilsBrokenSession->new(
					status => "Connection seems to be mangled: Got $mtype instead of CONNECT",
			);

			$session->status($res);
			$session->kill_me;
			return 0;

		}
		
		my $res = OpenSRF::DomainObject::oilsConnectStatus->new;
		$session->status($res);
		$session->state( $session->CONNECTED );

		return 0;
	}


	return 1;

}


# Handle client side message processing. Return 1 when the the message should be pushed
# up to the application layer.  return 0 otherwise.
sub do_client {

	my( $self, $session , $mtype, $api_level, $tT) = @_;


	if ($mtype eq 'STATUS') {

		if ($self->payload->statusCode == STATUS_OK) {
			$session->state($session->CONNECTED);
			$log->debug("We connected successfully to ".$session->app);
			return 0;
		}

		if ($self->payload->statusCode == STATUS_TIMEOUT) {
			$session->state( $session->DISCONNECTED );
			$session->reset;
			$session->connect;
			$session->push_resend( $session->app_request($self->threadTrace) );
			$log->debug("Disconnected because of timeout");
			return 0;

		} elsif ($self->payload->statusCode == STATUS_REDIRECTED) {
			$session->state( $session->DISCONNECTED );
			$session->reset;
			$session->connect;
			$session->push_resend( $session->app_request($self->threadTrace) );
			$log->debug("Disconnected because of redirect", WARN);
			return 0;

		} elsif ($self->payload->statusCode == STATUS_EXPFAILED) {
			$session->state( $session->DISCONNECTED );
			$log->debug("Disconnected because of mangled session", WARN);
			$session->reset;
			$session->push_resend( $session->app_request($self->threadTrace) );
			return 0;

		} elsif ($self->payload->statusCode == STATUS_CONTINUE) {
			$session->reset_request_timeout($self->threadTrace);
			return 0;

		} elsif ($self->payload->statusCode == STATUS_COMPLETE) {
			my $req = $session->app_request($self->threadTrace);
			$req->complete(1) if ($req);
			return 0;
		}

		# add more STATUS handling code here (as 'elsif's), for Message layer status stuff

		#$session->state( $session->DISCONNECTED() );
		#$session->reset;

	} elsif ($session->state == $session->CONNECTING()) {
		# This should be changed to check the type of response (is it a connectException?, etc.)
	}

	if( $self->payload and $self->payload->isa( "ERROR" ) ) { 
		if ($session->raise_remote_errors) {
			$self->payload->throw();
		}
	}

	$log->debug("oilsMessage passing to Application: " . $self->type." : ".$session->remote_id );

	return 1;

}

1;
