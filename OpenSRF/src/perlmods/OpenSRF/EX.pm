package OpenSRF::EX;
use Error qw(:try);
use base qw( OpenSRF Error );
use OpenSRF::Utils::Logger;

my $log = "OpenSRF::Utils::Logger";
$Error::Debug = 1;

sub new {
	my( $class, $message ) = @_;
	$class = ref( $class ) || $class;
	my $self = {};
	$self->{'msg'} = ${$class . '::ex_msg_header'} ." \n$message";
	return bless( $self, $class );
}	

sub message() { return $_[0]->{'msg'}; }

sub DESTROY{}


=head1 OpenSRF::EX

Top level exception.  This class logs an exception when it is thrown.  Exception subclasses
should subclass one of OpenSRF::EX::INFO, NOTICE, WARN, ERROR, CRITICAL, and PANIC and provide
a new() method that takes a message and a message() method that returns that message.

=cut

=head2 Synopsis


	throw OpenSRF::EX::Jabber ("I Am Dying");

	OpenSRF::EX::InvalidArg->throw( "Another way" );

	my $je = OpenSRF::EX::Jabber->new( "I Cannot Connect" );
	$je->throw();


	See OpenSRF/EX.pm for example subclasses.

=cut

# Log myself and throw myself

#sub message() { shift->alert_abstract(); }

#sub new() { shift->alert_abstract(); }

sub throw() {

	my $self = shift;

	if( ! ref( $self ) || scalar( @_ ) ) {
		$self = $self->new( @_ );
	}

	if(		$self->class->isa( "OpenSRF::EX::INFO" )	||
				$self->class->isa( "OpenSRF::EX::NOTICE" ) ||
				$self->class->isa( "OpenSRF::EX::WARN" ) ) {

		$log->debug( $self->stringify(), $log->DEBUG );
	}

	else{ $log->debug( $self->stringify(), $log->ERROR ); }
	
	$self->SUPER::throw;
}


sub stringify() {

	my $self = shift;
	my $ctime = localtime();
	my( $package, $file, $line) = get_caller();
	my $name = ref( $self );
	my $msg = $self->message();

	$msg =~ s/^/Mess: /mg;

	return "  * ! EXCEPTION ! * \nTYPE: $name\n$msg\n".
		"Loc.: $line $package \nLoc.: $file \nTime: $ctime\n";
}


# --- determine the originating caller of this exception
sub get_caller() {

	$package = caller();
	my $x = 0;
	while( $package->isa( "Error" ) || $package =~ /^Error::/ ) { 
		$package = caller( ++$x );
	}
	return (caller($x));
}




# -------------------------------------------------------------------
# -------------------------------------------------------------------

# Top level exception subclasses defining the different exception
# levels.

# -------------------------------------------------------------------

package OpenSRF::EX::INFO;
use base qw(OpenSRF::EX);
our $ex_msg_header = "System INFO";

# -------------------------------------------------------------------

package OpenSRF::EX::NOTICE;
use base qw(OpenSRF::EX);
our $ex_msg_header = "System NOTICE";

# -------------------------------------------------------------------

package OpenSRF::EX::WARN;
use base qw(OpenSRF::EX);
our $ex_msg_header = "System WARNING";

# -------------------------------------------------------------------

package OpenSRF::EX::ERROR;
use base qw(OpenSRF::EX);
our $ex_msg_header = "System ERROR";

# -------------------------------------------------------------------

package OpenSRF::EX::CRITICAL;
use base qw(OpenSRF::EX);
our $ex_msg_header = "System CRITICAL";

# -------------------------------------------------------------------

package OpenSRF::EX::PANIC;
use base qw(OpenSRF::EX);
our $ex_msg_header = "System PANIC";

# -------------------------------------------------------------------
# -------------------------------------------------------------------

# Some basic exceptions

# -------------------------------------------------------------------
package OpenSRF::EX::Jabber;
use base 'OpenSRF::EX::ERROR';
our $ex_msg_header = "Jabber Exception";

package OpenSRF::EX::JabberDisconnected;
use base 'OpenSRF::EX::ERROR';
our $ex_msg_header = "JabberDisconnected Exception";

=head2 OpenSRF::EX::Jabber

Thrown when there is a problem using the Jabber service

=cut

package OpenSRF::EX::Transport;
use base 'OpenSRF::EX::ERROR';
our $ex_msg_header = "Transport Exception";



# -------------------------------------------------------------------
package OpenSRF::EX::InvalidArg;
use base 'OpenSRF::EX::ERROR';
our $ex_msg_header = "Invalid Arg Exception";

=head2 OpenSRF::EX::InvalidArg

Thrown where an argument to a method was invalid or not provided

=cut


# -------------------------------------------------------------------
package OpenSRF::EX::NotADomainObject;
use base 'OpenSRF::EX::ERROR';
our $ex_msg_header = "Must be a Domain Object";

=head2 OpenSRF::EX::NotADomainObject

Thrown where a OpenSRF::DomainObject::oilsScalar or
OpenSRF::DomainObject::oilsPair was passed a value that
is not a perl scalar or a OpenSRF::DomainObject.

=cut


# -------------------------------------------------------------------
package OpenSRF::EX::ArrayOutOfBounds;
use base 'OpenSRF::EX::ERROR';
our $ex_msg_header = "Tied array access on a nonexistant index";

=head2 OpenSRF::EX::ArrayOutOfBounds

Thrown where a TIEd array (OpenSRF::DomainObject::oilsArray) was accessed at
a nonexistant index

=cut



# -------------------------------------------------------------------
package OpenSRF::EX::Socket;
use base 'OpenSRF::EX::ERROR';
our $ex_msg_header = "Socket Exception";

=head2 OpenSRF::EX::Socket

Thrown when there is a network layer exception

=cut



# -------------------------------------------------------------------
package OpenSRF::EX::Config;
use base 'OpenSRF::EX::PANIC';
our $ex_msg_header = "Config Exception";

=head2 OpenSRF::EX::Config

Thrown when a package requires a config option that it cannot retrieve
or the config file itself cannot be loaded

=cut


# -------------------------------------------------------------------
package OpenSRF::EX::User;
use base 'OpenSRF::EX::ERROR';
our $ex_msg_header = "User Exception";

=head2 OpenSRF::EX::User

Thrown when an error occurs due to user identification information

=cut

package OpenSRF::EX::Session;
use base 'OpenSRF::EX::ERROR';
our $ex_msg_header = "Session Error";


1;
