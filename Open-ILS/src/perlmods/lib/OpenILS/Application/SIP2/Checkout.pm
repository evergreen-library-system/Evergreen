package OpenILS::Application::SIP2::Checkout;
use strict; use warnings;
use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::SIP2::Common;
my $U = 'OpenILS::Application::AppUtils';
my $SC = 'OpenILS::Application::SIP2::Common';


# Returns the 'circ' object on success, undef on error.
sub checkout {
    my ($class, $session, %params) = @_;

    my $circ_details = {};
    my $override = 0;

    for (0, 1) { # 2 checkout requests max

        $override = 
            perform_checkout($session, $circ_details, $override, %params);

        last unless $override;
    }

    return $circ_details;
}

sub renew_all {
    my ($class, $session, $patron_details, %params) = @_;

    my $circ_details = {};

    my @circ_ids = (
        @{$patron_details->{items_out_ids}}, 
        @{$patron_details->{items_overdue_ids}}
    );

    my @renewed;
    my @unrenewed;
    for my $circ_id (@circ_ids) {

        my $circ = $session->editor->retrieve_action_circulation([
            $circ_id, {flesh => 1, flesh_fields => {circ => ['target_copy']}}]);

        my $item_barcode = $circ->target_copy->barcode;

        my $detail = $class->checkout($session, 
            item_barcode => $item_barcode,
            fee_ack => $params{fee_ack},
            is_renew => 1
        );

        if ($detail->{ok}) {
            push(@renewed, $item_barcode);
        } else {
            push(@unrenewed, $item_barcode);
        }
    }

    $circ_details->{items_renewed} = \@renewed;
    $circ_details->{items_unrenewed} = \@unrenewed;

    return $circ_details;
}

# Returns 1 if the checkout should be performed again with override.
# Returns 0 if there's nothing left to do (final success / error)
# Updates $circ_details along the way.
sub perform_checkout {
    my ($session, $circ_details, $override, %params) = @_;
    my $config = $session->config;

    my $action = $params{is_renew} ? 'renew' : 'checkout';

    my $args = {
        copy_barcode => $params{item_barcode},
        # During renewal, the circ API will confirm the specified
        # patron has the specified item checked out before renewing.
        patron_barcode => $params{patron_barcode}
    };

    my $method = $action eq 'renew' ?
        'open-ils.circ.renew' : 'open-ils.circ.checkout.full';

    $method .= '.override' if $override;

    my $resp = $U->simplereq(
        'open-ils.circ', $method, $session->editor->authtoken, $args);

    $resp = [$resp] unless ref $resp eq 'ARRAY';

    for my $event (@$resp) {
        next unless $U->is_event($event); # this should never happen.
        my $textcode = $event->{textcode};

        if ($textcode eq 'SUCCESS' && $event->{payload}) {
            $circ_details->{ok} = 1;
            if (my $circ = $event->{payload}->{circ}) {
                $circ_details->{circ} = $circ;

                my $due_date= 
                    DateTime::Format::ISO8601->new
                        ->parse_datetime(clean_ISO8601($circ->due_date));

                $circ_details->{due_date} =
                    $config->{settings}->{due_date_use_sip_date_format} ?
                    $SC->sipdate($due_date) :
                    $due_date->strftime('%F %T');

                return 0;
            }
        }

        if (!$override) {
            if ($config->{settings}->{"$action.override.$textcode"}) {
                # Event type is configured for override;
                return 1;

            } elsif ($params{fee_ack} &&
                $textcode =~ /ITEM_(?:DEPOSIT|RENTAL)_FEE_REQUIRED/ ) {
                # Patron acknowledged the fee.  Redo with override.
                return 1;
            }
        }

        if ($textcode eq 'OPEN_CIRCULATION_EXISTS' ) {
            my $msg = $session->editor
                ->retrieve_sip_screen_message('checkout.open_circ_exists');

            $circ_details->{screen_msg} = 
                $msg ? $msg->message : 'This item is already checked out';

        } else {

            my $msg = 
                $session->editor
                    ->retrieve_sip_screen_message('checkout.patron_not_allowed');

            $circ_details->{screen_msg} = $msg ? $msg->message : 
                'Patron is not allowed to checkout the selected item';
        }
    }

    return 0;
}


1;
