#
# An object to handle checkout status
#

package OpenILS::SIP::Transaction::Checkout;

use warnings;
use strict;

use POSIX qw(strftime);

use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use OpenILS::SIP::Msg qw/:const/;
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
	my $is_renew = shift || 0;

	$self->ok(0); 

	my $args = { 
		barcode => $self->{item}->id, 
		patron_barcode => $self->{patron}->id
	};

	my $resp;

	if ($is_renew) {
		$resp = $U->simplereq(
			'open-ils.circ',
			'open-ils.circ.renew', $self->{authtoken},
			{ barcode => $self->item->id, patron_barcode => $self->patron->id });
	} else {
		$resp = $U->simplereq(
			'open-ils.circ',
			'open-ils.circ.checkout.permit', 
			$self->{authtoken}, $args );

		$resp = [$resp] unless ref $resp eq 'ARRAY';

		my $key;

		syslog('LOG_DEBUG', "OILS: Checkout permit returned event: " . OpenSRF::Utils::JSON->perl2JSON($resp));

		if( @$resp == 1 and ! $U->event_code($$resp[0]) ) {
			$key = $$resp[0]->{payload};
			syslog('LOG_INFO', "OILS: circ permit key => $key");

		} else {

			# We got one or more non-success events
			$self->screen_msg('');
			for my $r (@$resp) {

				if( my $code = $U->event_code($resp) ) {
					my $txt = $resp->{textcode};
					syslog('LOG_INFO', "OILS: Checkout permit failed with event $code : $txt");

					if( $txt eq 'OPEN_CIRCULATION_EXISTS' ) {
						$self->screen_msg(OILS_SIP_MSG_CIRC_EXISTS);
						return 0;
					} else {
						$self->screen_msg(OILS_SIP_MSG_CIRC_PERMIT_FAILED);
					}
				}
			}
			return 0;
		}

		# --------------------------------------------------------------------
		# Now do the actual checkout
		# --------------------------------------------------------------------

		$args = { 
			permit_key		=> $key, 
			patron_barcode => $self->{patron}->id, 
			barcode			=> $self->{item}->id
		};

		$resp = $U->simplereq(
			'open-ils.circ',
			'open-ils.circ.checkout', $self->{authtoken}, $args );
	}

	syslog('LOG_INFO', "OILS: Checkout returned event: " . OpenSRF::Utils::JSON->perl2JSON($resp));

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
		$self->{'due'} = OpenILS::SIP->format_date($circ->due_date, 'due');
		$self->ok(1);

		return 1;
	}

	return 0;
}



1;
