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

    $self->load_override_events;

    return bless $self, $class;
}

# Lifted from Checkin.pm to load the list of events that we'll try to
# override if they occur during checkout or renewal.
my %override_events;
sub load_override_events {
    return if %override_events;
    my $override = OpenILS::SIP->config->{implementation_config}->{checkout_override};
    return unless $override;
    my $events = $override->{event};
    $events = [$events] unless ref $events eq 'ARRAY';
    $override_events{$_} = 1 for @$events;
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

    my ($resp, $method);

    my $override = 0;

    if ($is_renew) {
        $method = 'open-ils.circ.renew';
    } else {
        $method = 'open-ils.circ.checkout.full';
    }

    while (1) {
        $method .= '.override' if ($override);
        $resp = $U->simplereq('open-ils.circ', $method, $self->{authtoken}, $args);

        $resp = [$resp] unless ref $resp eq 'ARRAY';

        syslog('LOG_DEBUG', "OILS: $method returned event: " . OpenSRF::Utils::JSON->perl2JSON($resp));

        my $first_code = $U->event_code($$resp[0]);
        if (@$resp > 1 || !defined $first_code || $first_code ne '0') {
            # We got one or more non-success events
            $self->screen_msg('');
            for my $r (@$resp) {
                my $code = $U->event_code($r);
                my $txt = $r->{textcode};
                syslog('LOG_INFO', "OILS: $method failed with event $code : $txt");

                if ($override_events{$txt} && $method !~ /override$/) {
                    # Found an event we've been configured to override.
                    $override = 1;
                } elsif ($txt =~ /ITEM_(?:DEPOSIT|RENTAL)_FEE_REQUIRED/ && $self->fee_ack) {
                    # Patron acknowledged the fee.
                    $override = 1;
                } elsif ( $txt eq 'OPEN_CIRCULATION_EXISTS' ) {
                    $self->screen_msg(OILS_SIP_MSG_CIRC_EXISTS);
                    return 0;
                } else {
                    $self->screen_msg(OILS_SIP_MSG_CIRC_PERMIT_FAILED);
                    return 0;
                }
            }
            # This looks potentially dangerous, but we shouldn't
            # end up here if the loop iterated with $override = 1;
            next if ($override && $method !~ /override$/);
        } else {
            # We appear to have success.
            # De-arrayify the response.
            $resp = $$resp[0];

            syslog('LOG_INFO', "OILS: $method succeeded");

            my $circ = $resp->{payload}->{circ};
            $self->{'due'} = OpenILS::SIP->format_date($circ->due_date, 'due');
            $self->ok(1);
            last;

        }
        last if ($method =~ /override$/);
    }


    return $self->ok;
}



1;
