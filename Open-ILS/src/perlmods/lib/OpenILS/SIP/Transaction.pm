#
# Transaction: Superclass of all the transactional status objects
#

package OpenILS::SIP::Transaction;

use Carp;
use strict; use warnings;
use Sys::Syslog qw(syslog);

use OpenILS::SIP;
use OpenILS::SIP::Msg qw/:const/;


my %fields = (
      ok            => 0,
      patron        => undef,
      item          => undef,
      desensitize   => 0,
      alert         => '',
      transaction_id => undef,
      sip_fee_type  => '01', # Other/Unknown
      fee_amount    => undef,
      sip_currency  => 'CAD',
      screen_msg    => '',
      print_line    => '',
      editor        => undef,
      authtoken     => '',
      fee_ack       => 0,
);

our $AUTOLOAD;

sub new {
    my( $class, %args ) = @_;

    my $self = { _permitted => \%fields, %fields };

    bless $self, $class;
    $self->authtoken($args{authtoken});

    syslog('LOG_DEBUG', "OILS: Created new transaction with authtoken %s", $self->authtoken);

    my $e = OpenILS::SIP->editor();
    $e->{authtoken} = $self->authtoken;

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
