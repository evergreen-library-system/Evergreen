package OpenSRF::DomainObject::oilsResponse;
use vars qw/@EXPORT_OK %EXPORT_TAGS/;
use Exporter;
use JSON;
use base qw/OpenSRF::DomainObject Exporter/;
use OpenSRF::Utils::Logger qw/:level/;

BEGIN {
@EXPORT_OK = qw/STATUS_CONTINUE STATUS_OK STATUS_ACCEPTED
					STATUS_BADREQUEST STATUS_UNAUTHORIZED STATUS_FORBIDDEN
					STATUS_NOTFOUND STATUS_NOTALLOWED STATUS_TIMEOUT
					STATUS_INTERNALSERVERERROR STATUS_NOTIMPLEMENTED
					STATUS_VERSIONNOTSUPPORTED STATUS_REDIRECTED 
					STATUS_EXPFAILED STATUS_COMPLETE/;

%EXPORT_TAGS = (
	status => [ qw/STATUS_CONTINUE STATUS_OK STATUS_ACCEPTED
					STATUS_BADREQUEST STATUS_UNAUTHORIZED STATUS_FORBIDDEN
					STATUS_NOTFOUND STATUS_NOTALLOWED STATUS_TIMEOUT
					STATUS_INTERNALSERVERERROR STATUS_NOTIMPLEMENTED
					STATUS_VERSIONNOTSUPPORTED STATUS_REDIRECTED 
					STATUS_EXPFAILED STATUS_COMPLETE/ ],
);

}

=head1 NAME

OpenSRF::DomainObject::oilsResponse

=head1 SYNOPSIS

use OpenSRF::DomainObject::oilsResponse qw/:status/;

my $resp = OpenSRF::DomainObject::oilsResponse->new;

$resp->status( 'a status message' );

$resp->statusCode( STATUS_CONTINUE );

$client->respond( $resp );

=head1 ABSTRACT

OpenSRF::DomainObject::oilsResponse implements the base class for all Application
layer messages send between the client and server.

=cut

sub STATUS_CONTINUE		{ return 100 }

sub STATUS_OK				{ return 200 }
sub STATUS_ACCEPTED		{ return 202 }
sub STATUS_COMPLETE		{ return 205 }

sub STATUS_REDIRECTED	{ return 307 }

sub STATUS_BADREQUEST	{ return 400 }
sub STATUS_UNAUTHORIZED	{ return 401 }
sub STATUS_FORBIDDEN		{ return 403 }
sub STATUS_NOTFOUND		{ return 404 }
sub STATUS_NOTALLOWED	{ return 405 }
sub STATUS_TIMEOUT		{ return 408 }
sub STATUS_EXPFAILED		{ return 417 }

sub STATUS_INTERNALSERVERERROR	{ return 500 }
sub STATUS_NOTIMPLEMENTED			{ return 501 }
sub STATUS_VERSIONNOTSUPPORTED	{ return 505 }

my $log = 'OpenSRF::Utils::Logger';

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	my $default_status = eval "\$${class}::status";
	my $default_statusCode = eval "\$${class}::statusCode";

	my %args = (	status => $default_status,
			statusCode => $default_statusCode,
			@_ );
	
	return $class->SUPER::new( %args );
}

sub status {
	my $self = shift;
	return $self->_attr_get_set( status => shift );
}

sub statusCode {
	my $self = shift;
	return $self->_attr_get_set( statusCode => shift );
}


#-------------------------------------------------------------------------------



package OpenSRF::DomainObject::oilsStatus;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use base 'OpenSRF::DomainObject::oilsResponse';
use vars qw/$status $statusCode/;

=head1 NAME

OpenSRF::DomainObject::oilsException

=head1 SYNOPSIS

use OpenSRF::DomainObject::oilsResponse;

...

# something happens.

$client->status( OpenSRF::DomainObject::oilsStatus->new );

=head1 ABSTRACT

The base class for Status messages sent between client and server.  This
is implemented on top of the C<OpenSRF::DomainObject::oilsResponse> class, and 
sets the default B<status> to C<Status> and B<statusCode> to C<STATUS_OK>.

=cut

$status = 'Status';
$statusCode = STATUS_OK;

package OpenSRF::DomainObject::oilsConnectStatus;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use base 'OpenSRF::DomainObject::oilsStatus';
use vars qw/$status $statusCode/;

=head1 NAME

OpenSRF::DomainObject::oilsConnectStatus

=head1 SYNOPSIS

use OpenSRF::DomainObject::oilsResponse;

...

# something happens.

$client->status( new OpenSRF::DomainObject::oilsConnectStatus );

=head1 ABSTRACT

The class for Stati relating to the connection status of a session.  This
is implemented on top of the C<OpenSRF::DomainObject::oilsStatus> class, and 
sets the default B<status> to C<Connection Successful> and B<statusCode> to C<STATUS_OK>.

=head1 SEE ALSO

B<OpenSRF::DomainObject::oilsStatus>

=cut

$status = 'Connection Successful';
$statusCode = STATUS_OK;

1;



#-------------------------------------------------------------------------------



package OpenSRF::DomainObject::oilsResult;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::DomainObject::oilsPrimitive;
use base 'OpenSRF::DomainObject::oilsResponse';
use vars qw/$status $statusCode/;


$status = 'OK';
$statusCode = STATUS_OK;

=head1 NAME

OpenSRF::DomainObject::oilsResult

=head1 SYNOPSIS

use OpenSRF::DomainObject::oilsResponse;

 .... do stuff, create $object ...

my $res = OpenSRF::DomainObject::oilsResult->new;

$res->content($object)

$session->respond( $res );

=head1 ABSTRACT

This is the base class for encapuslating RESULT messages send from the server
to a client.  It is a subclass of B<OpenSRF::DomainObject::oilsResponse>, and
sets B<status> to C<OK> and B<statusCode> to C<STATUS_OK>.

=head1 METHODS

=head2 OpenSRF::DomainObject::oilsMessage->content( [$new_content] )

=over 4

Sets or gets the content of the response.  This should be exactly one object
of (sub)type domainObject or domainObjectCollection.

=back

=cut

sub content {
        my $self = shift;
	my $new_content = shift;

	my ($content) = $self->getChildrenByTagName('oils:domainObject');

	if (defined $new_content) {
		$new_content = OpenSRF::DomainObject::oilsScalar->new( JSON->perl2JSON( $new_content ) );

		$self->removeChild($content) if ($content);
		$self->appendChild($new_content);
	}


	$new_content = $content if ($content);

	return JSON->JSON2perl($new_content->textContent) if $new_content;
}

=head1 SEE ALSO

B<OpenSRF::DomainObject::oilsResponse>

=cut

1;



#-------------------------------------------------------------------------------



package OpenSRF::DomainObject::oilsException;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::EX;
use base qw/OpenSRF::EX OpenSRF::DomainObject::oilsResponse/;
use vars qw/$status $statusCode/;
use Error;

sub message {
	my $self = shift;
	return '<' . $self->statusCode . '>  ' . $self->status;
}

sub new {
	my $class = shift;
	return $class->OpenSRF::DomainObject::oilsResponse::new( @_ );
}


=head1 NAME

OpenSRF::DomainObject::oilsException

=head1 SYNOPSIS

use OpenSRF::DomainObject::oilsResponse;

...

# something breaks.

$client->send( 'ERROR', OpenSRF::DomainObject::oilsException->new( status => "ARRRRRRG!" ) );

=head1 ABSTRACT

The base class for Exception messages sent between client and server.  This
is implemented on top of the C<OpenSRF::DomainObject::oilsResponse> class, and 
sets the default B<status> to C<Exception occured> and B<statusCode> to C<STATUS_BADREQUEST>.

=cut

$status = 'Exception occured';
$statusCode = STATUS_INTERNALSERVERERROR;

package OpenSRF::DomainObject::oilsConnectException;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::EX;
use base qw/OpenSRF::DomainObject::oilsException OpenSRF::EX::ERROR/;
use vars qw/$status $statusCode/;

=head1 NAME

OpenSRF::DomainObject::oilsConnectException

=head1 SYNOPSIS

use OpenSRF::DomainObject::oilsResponse;

...

# something breaks while connecting.

$client->send( 'ERROR', new OpenSRF::DomainObject::oilsConnectException );

=head1 ABSTRACT

The class for Exceptions that occur durring the B<CONNECT> phase of a session.  This
is implemented on top of the C<OpenSRF::DomainObject::oilsException> class, and 
sets the default B<status> to C<Connect Request Failed> and B<statusCode> to C<STATUS_FORBIDDEN>.

=head1 SEE ALSO

B<OpenSRF::DomainObject::oilsException>

=cut


$status = 'Connect Request Failed';
$statusCode = STATUS_FORBIDDEN;

package OpenSRF::DomainObject::oilsMethodException;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use base 'OpenSRF::DomainObject::oilsException';
use vars qw/$status $statusCode/;

=head1 NAME

OpenSRF::DomainObject::oilsMehtodException

=head1 SYNOPSIS

use OpenSRF::DomainObject::oilsResponse;

...

# something breaks while looking up or starting
# a method call.

$client->send( 'ERROR', new OpenSRF::DomainObject::oilsMethodException );

=head1 ABSTRACT

The class for Exceptions that occur durring the B<CONNECT> phase of a session.  This
is implemented on top of the C<OpenSRF::DomainObject::oilsException> class, and 
sets the default B<status> to C<Connect Request Failed> and B<statusCode> to C<STATUS_NOTFOUND>.

=head1 SEE ALSO

B<OpenSRF::DomainObject::oilsException>

=cut


$status = 'Method not found';
$statusCode = STATUS_NOTFOUND;

# -------------------------------------------

package OpenSRF::DomainObject::oilsServerError;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use base 'OpenSRF::DomainObject::oilsException';
use vars qw/$status $statusCode/;

$status = 'Internal Server Error';
$statusCode = STATUS_INTERNALSERVERERROR;

# -------------------------------------------





package OpenSRF::DomainObject::oilsBrokenSession;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::EX;
use base qw/OpenSRF::DomainObject::oilsException OpenSRF::EX::ERROR/;
use vars qw/$status $statusCode/;
$status = "Request on Disconnected Session";
$statusCode = STATUS_EXPFAILED;

package OpenSRF::DomainObject::oilsXMLParseError;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::EX;
use base qw/OpenSRF::DomainObject::oilsException OpenSRF::EX::ERROR/;
use vars qw/$status $statusCode/;
$status = "XML Parse Error";
$statusCode = STATUS_EXPFAILED;

package OpenSRF::DomainObject::oilsAuthException;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::EX;
use base qw/OpenSRF::DomainObject::oilsException OpenSRF::EX::ERROR/;
use vars qw/$status $statusCode/;
$status = "Authentication Failure";
$statusCode = STATUS_FORBIDDEN;

1;
