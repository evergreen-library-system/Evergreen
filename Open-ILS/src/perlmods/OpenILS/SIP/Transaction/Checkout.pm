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
	syslog('LOG_DEBUG', "OILS: performing checkout...");

	$self->ok(0); 

	my $args = { 
		barcode => $self->{item}->id, 
		patron_barcode => $self->{patron}->id
	};

	my $resp = $U->simplereq(
		'open-ils.circ',
		'open-ils.circ.checkout.permit', 
		$self->{authtoken}, $args );

	if( ref($resp) eq 'ARRAY' ) {
		my @e;
		push( @e, $_->{textcode} ) for @$resp;
		syslog('LOG_INFO', "OILS: Checkout permit failed with events: @e");
		$self->screen_msg('Patron is not allowed to check out the selected item');
		return 0;
	}

	if( my $code = $U->event_code($resp) ) {
		my $txt = $resp->{textcode};
		syslog('LOG_INFO', "OILS: Checkout permit failed with event $code : $txt");
		$self->screen_msg('Patron is not allowed to check out the selected item');
		return 0; 
	}

	my $key;

	if( $key = $resp->{payload} ) {
		syslog('LOG_INFO', "OILS: circ permit key => $key");

	} else {
		syslog('LOG_WARN', "OILS: Circ permit failed :\n" . Dumper($resp) );
		$self->screen_msg('Patron is not allowed to check out the selected item');
		return 0;
	}

	# Now do the actual checkout

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

		if( my $code = $U->event_code($resp) ) {
			my $txt = $resp->{textcode};
			syslog('LOG_INFO', "OILS: Checkout failed with event $code : $txt");
			$self->screen_msg('Checkout failed.  Please contact a librarian');
			return 0; 
		}

		syslog('LOG_INFO', "OILS: Checkout succeeded");

		my $circ = $resp->{payload}->{circ};
		$self->{'due'} = OpenILS::SIP->format_date($circ->due_date);
		$self->ok(1);

		return 1;
	}

	return 0;
}



1;
