package OpenSRF::DomainObject::oilsMessage;
use base 'OpenSRF::DomainObject';
use OpenSRF::AppSession;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::Utils::Logger qw/:level/;
use warnings; use strict;
use OpenSRF::EX qw/:try/;

=head1 NAME

OpenSRF::DomainObject::oilsMessage

=head1

use OpenSRF::DomainObject::oilsMessage;

my $msg = OpenSRF::DomainObject::oilsMessage->new( type => 'CONNECT' );

$msg->userAuth( $userAuth_element );

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
	return $self->_attr_get_set( type => shift );
}

=head2 OpenSRF::DomainObject::oilsMessage->protocol( [$new_protocol_number] )

=over 4

Used to specify the protocol of message.  Currently, only protocol C<1> is
supported.  This will be used to check that messages are well-formed, and as
a hint to the Application as to which version of a method should fulfill a
REQUEST message.

=back

=cut

sub protocol {
	my $self = shift;
	return $self->_attr_get_set( protocol => shift );
}

=head2 OpenSRF::DomainObject::oilsMessage->threadTrace( [$new_threadTrace] );

=over 4

Sets or gets the current message sequence identifier, or thread trace number,
for a message.  Useful as a debugging aid, but that's about it.

=back

=cut

sub threadTrace {
	my $self = shift;
	return $self->_attr_get_set( threadTrace => shift );
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
	my $new_pl = shift;

	my ($payload) = $self->getChildrenByTagName('oils:domainObjectCollection') ||
				$self->getChildrenByTagName('oils:domainObject');
	if ($new_pl) {
		$payload = $self->removeChild($payload) if ($payload);
		$self->appendChild($new_pl);
		return $new_pl unless ($payload);
	}

	return OpenSRF::DOM::upcast($payload)->upcast if ($payload);
}

=head2 OpenSRF::DomainObject::oilsMessage->userAuth( [$new_userAuth_element] )

=over 4

Sets or gets the userAuth element for this message.  This is used internally by the
session object.

=back

=cut

sub userAuth {
	my $self = shift;
	my $new_ua = shift;

	my ($ua) = $self->getChildrenByTagName('oils:userAuth');
	if ($new_ua) {
		$ua = $self->removeChild($ua) if ($ua);
		$self->appendChild($new_ua);
		return $new_ua unless ($ua);
	}

	return $ua;
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
	my $protocol = $self->protocol || 1;;
	my $tT = $self->threadTrace;

	$session->last_message_type($mtype);
	$session->last_message_protocol($protocol);
	$session->last_threadTrace($tT);

	$log->debug(" Received protocol => [$protocol], MType => [$mtype], ".
			"from [".$session->remote_id."], threadTrace[".$self->threadTrace."]", INFO);
	$log->debug("endpoint => [".$session->endpoint."]", DEBUG);
	$log->debug("OpenSRF::AppSession->SERVER => [".$session->SERVER()."]", DEBUG);

	$log->debug("Before ALL", DEBUG);

	my $val;
	if ( $session->endpoint == $session->SERVER() ) {
		$val = $self->do_server( $session, $mtype, $protocol, $tT );

	} elsif ($session->endpoint == $session->CLIENT()) {
		$val = $self->do_client( $session, $mtype, $protocol, $tT );
	}

	if( $val ) {
		return OpenSRF::Application->handler($session, $self->payload);
	}

	return 1;

}



# handle server side message processing

# !!! Returning 0 means that we don't want to pass ourselves up to the message layer !!!
sub do_server {
	my( $self, $session, $mtype, $protocol, $tT ) = @_;

	# A Server should never receive STATUS messages.  If so, we drop them.
	# This is to keep STATUS's from dead client sessions from creating new server
	# sessions which send mangled session exceptions to backends for messages 
	# that they are not aware of any more.
	if( $mtype eq 'STATUS' ) { return 0; }

	
	if ($mtype eq 'DISCONNECT') {
		$session->state( $session->DISCONNECTED );
		$session->kill_me;
		return 0;
	}

	if ($session->state == $session->CONNECTING()) {

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
		
		#unless ($self->userAuth ) {
		#	$log->debug( "No Authentication information was provided with the initial packet", ERROR );
		#	my $res = OpenSRF::DomainObject::oilsConnectException->new(
		#			status => "No Authentication info was provided with initial message" );
		#	$session->status($res);
		#	$session->kill_me;
		#	return 0;
		#}

		#unless( $self->userAuth->authenticate( $session ) ) {
		#	my $res = OpenSRF::DomainObject::oilsAuthException->new(
		#		status => "Authentication Failed for " . $self->userAuth->getAttribute('username') );
		#	$session->status($res) if $res;
		#	$session->kill_me;
		#	return 0;
		#}

		#$session->client_auth( $self->userAuth );

		$log->debug("We're a server and the user is authenticated",DEBUG);

		my $res = OpenSRF::DomainObject::oilsConnectStatus->new;
		$session->status($res);
		$session->state( $session->CONNECTED );

		return 0;
	}


	$log->debug("Passing to Application::handler()", INFO);
	$log->debug($self->toString(1), DEBUG);

	return 1;

}


# Handle client side message processing. Return 1 when the the message should be pushed
# up to the application layer.  return 0 otherwise.
sub do_client {

	my( $self, $session , $mtype, $protocol, $tT) = @_;


	if ($mtype eq 'STATUS') {

		if ($self->payload->statusCode == STATUS_OK) {
			$session->state($session->CONNECTED);
			$log->debug("We connected successfully to ".$session->app, INFO);
			return 0;
		}

		if ($self->payload->statusCode == STATUS_TIMEOUT) {
			$session->state( $session->DISCONNECTED );
			$session->reset;
			$session->push_resend( $session->app_request($self->threadTrace) );
			$log->debug("Disconnected because of timeout", WARN);
			return 0;

		} elsif ($self->payload->statusCode == STATUS_REDIRECTED) {
			$session->state( $session->DISCONNECTED );
			$session->reset;
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
			return 0;

		} elsif ($self->payload->statusCode == STATUS_COMPLETE) {
			my $req = $session->app_request($self->threadTrace);
			$req->complete(1) if ($req);
			return 0;
		}

		# add more STATUS handling code here (as 'elsif's), for Message layer status stuff

	} elsif ($session->state == $session->CONNECTING()) {
		# This should be changed to check the type of response (is it a connectException?, etc.)
	}

	if( $self->payload->class->isa( "OpenSRF::EX" ) ) { 
		$self->payload->throw();
	}

	$log->debug("Passing to OpenSRF::Application::handler()\n" . $self->payload->toString(1), INTERNAL);
	$log->debug("oilsMessage passing to Application: " . $self->type." : ".$session->remote_id, INFO );

	return 1;

}

1;
