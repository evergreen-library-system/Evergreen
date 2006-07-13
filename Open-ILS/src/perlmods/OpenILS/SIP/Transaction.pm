#
# Transaction: Superclass of all the transactional status objects
#

package OpenILS::SIP::Transaction;

use Carp;
use strict; use warnings;
use Sys::Syslog qw(syslog);


my %fields = (
	      ok            => 0,
	      patron        => undef,
	      item          => undef,
	      desensitize   => 0,
	      alert         => '',
	      transation_id => undef,
	      sip_fee_type  => '01', # Other/Unknown
	      fee_amount    => undef,
	      sip_currency  => 'CAD',
	      screen_msg    => '',
	      print_line    => '',
			editor			=> undef,
			authtoken		=> '',
	      );

our $AUTOLOAD;

# returns the global transaction pointer
#sub get_xact {
#	my $class = shift;
#	return $XACT;
#}
#
#sub session {
#	my( $self, $session ) = @_;
#	$self->{session} = $session if $session;
#	return $self->{session};
#}
#
#
#sub create_session {
#	my( $self, $patron ) = @_;
#	$self->commit_session if $self->session_is_alive;
#	require OpenILS::Utils::CStoreEditor;
#	return $self->{session} = {
#		editor => OpenILS::Utils::CStoreEditor->new(xact=>1),
#		patron => $patron
#	}
#}
#
#sub commit_session {
#	my $self = shift;
#	if( my $session = $self->session ) {
#		$session->{editor}->commit;
#		delete $$session{editor};
#		delete $$session{patron};
#	}
#}
#
#
#sub rollback_session {
#	my $self = shift;
#	if( my $session = $self->session ) {
#		$session->{editor}->xact_rollback;
#		delete $$session{editor};
#		delete $$session{patron};
#	}
#}
#
#sub session_is_alive {
#	my $self = shift;
#	return $self->session and $self->session->{editor};
#}



sub new {
    my( $class, %args ) = @_;

	use Data::Dumper;
	warn 'ARGS = ' .  Dumper(\@_);

	warn "AUTH = " . $args{authtoken} . "\n";

    my $self = {
		_permitted => \%fields,
		%fields,
    };

	bless $self, $class;
	$self->authtoken($args{authtoken});

	syslog('LOG_DEBUG', "OpenILS: Created new transaction with authtoken %s", $self->authtoken);

	require OpenILS::Utils::CStoreEditor;
	$self->editor(OpenILS::Utils::CStoreEditor->new(
		xact=>1, authtoken => $self->authtoken));

	return $self;
}

sub DESTROY {
    # be cool
}

sub AUTOLOAD {
    my $self = shift;
    my $class = ref($self) or croak "$self is not an object";
    my $name = $AUTOLOAD;

    $name =~ s/.*://;

    unless (exists $self->{_permitted}->{$name}) {
	croak "Can't access '$name' field of class '$class'";
    }

    if (@_) {
	return $self->{$name} = shift;
    } else {
	return $self->{$name};
    }
}

1;
