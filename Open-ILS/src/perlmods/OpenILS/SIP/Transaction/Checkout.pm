#
# An object to handle checkout status
#

package OpenILS::SIP::Transaction::Checkout;

use warnings;
use strict;

use POSIX qw(strftime);

use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use Sys::Syslog qw(syslog);

use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';


our @ISA = qw(OpenILS::SIP::Transaction);

# Most fields are handled by the Transaction superclass
my %fields = (
	      security_inhibit => 0,
	      due              => undef,
	      renew_ok         => 0,
	      );

sub new {
	 my $class = shift;

	 use Data::Dumper;
	 warn 'ARGS = ' .  Dumper(\@_);

    my $self = $class->SUPER::new(@_);

    my $element;

	foreach $element (keys %fields) {
		$self->{_permitted}->{$element} = $fields{$element};
	}

    @{$self}{keys %fields} = values %fields;
	 
    return bless $self, $class;
}


# if this item is already checked out to the requested patron,
# renew the item and set $self->renew_ok to true.  
# XXX if it's a renewal and the renewal is not permitted, set 
# $self->screen_msg("Item on Hold for Another User"); (or somesuch)
# XXX Set $self->ok(0) on any errors
sub do_checkout {
	my $self = shift;
	syslog('LOG_DEBUG', "OpenILS: performing checkout...");

	my $args = { 
		barcode => $self->{item}->id, 
		patron_barcode => $self->{patron}->id
	};

	my $resp = $U->simplereq(
		'open-ils.circ',
		'open-ils.circ.checkout.permit', 
		$self->{authtoken}, $args );

	my $key;

	if( ref($resp) eq 'HASH' and $key = $resp->{payload} ) {
		syslog('LOG_INFO', "OpenILS: circ permit key => $key");

	} else {
		syslog('LOG_INFO', "OpenILS: Circ permit failed :\n" . Dumper($resp) );
		$self->ok(0);
		return 0;
	}

	$args = { 
		permit_key		=> $key, 
		patron_barcode => $self->{patron}->id, 
		barcode			=> $self->{item}->id
	};

	$resp = $U->simplereq(
		'open-ils.circ',
		'open-ils.circ.checkout', $self->{authtoken}, $args );

	# XXX Check for events
	if( $resp ) {
		syslog('LOG_INFO', "OpenILS: Checkout succeeded");
		my $evt = $resp->{ilsevent};
		my $circ = $resp->{payload}->{circ};

		if(!$circ or $evt ne 0) { 
			$self->ok(0); 
			warn 'CHECKOUT RESPONSE: ' .  Dumper($resp) . "\n";
			return 0; 
		}

		$self->{'due'} = $circ->due_date;
		$self->ok(1);
		return 1;
	}

	return 0;
}



1;
