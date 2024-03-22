package OpenILS::Application::SIP2::Checkin;
use strict; use warnings;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::System;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Const qw/:const/;
use OpenILS::Application::SIP2::Common;
use OpenILS::Application::SIP2::Session;
my $U = 'OpenILS::Application::AppUtils';
my $SC = 'OpenILS::Application::SIP2::Common';


sub checkin {
    my ($class, $session, %params) = @_;

    my $details = {};
    my $override = 0;

    for (0, 1) { # 2 checkin requests max

        $override = perform_checkin($session, $details, $override, %params);

        last unless $override;
    }
    
    return $details;
}


# Returns 1 if the checkin should be performed again with override.
# Returns 0 if there's nothing left to do (final success / error)
# Updates $details along the way.
sub perform_checkin {
    my ($session, $details, $override, %params) = @_;
    my $config = $session->config;
    my $item_details = $params{item_details};

    my $args = {
        copy_barcode => $params{item_barcode},
        hold_as_transit => $config->{checkin_hold_as_transit}
    };

    if (my $backdate = $params{return_date}) {
        $backdate =~ s/(\d{4})(\d{2})(\d{2}).*/$1-$2-$3/; # YYYYMMDD => ISO
        $logger->info("Checking in with backdate $backdate");
        $args->{backdate} = $backdate;
    }

    $args->{circ_lib} = 
        $SC->org_id_from_sn($session, $params{current_loc}) 
        || $session->editor->requestor->ws_ou;

    my $method = 'open-ils.circ.checkin';
    $method .= '.override' if $override;

    my $resp = $U->simplereq(
        'open-ils.circ', $method, $session->editor->authtoken, $args);

    # Treat the first response as the main result.
    my $event = ref $resp eq 'ARRAY' ? $resp->[0] : $resp;

    return unless $U->is_event($event); # should never happen; fail gracefully

    my $textcode = $event->{textcode};
    my $payload = $event->{payload} || {};

    return 1 if !$override && $config->{"checkin.override.$textcode"};

    my $circ = $payload->{circ};
    my $copy = $payload->{copy};

    # These may be replaced below
    $details->{current_loc} = 
        $params{item_details}->{item}->circ_lib->shortname;

    $details->{permanent_loc} = 
        $params{item_details}->{item}->circ_lib->shortname;

    $details->{destination_loc} = 
        $SC->org_sn_from_id($event->{org}) if $event->{org};

   if ($copy && $copy->circ_lib != $item_details->{item}->circ_lib->id) {
        # Checkin of floating copies changes the circ lib.
        $details->{current_loc} = 
            $details->{permanent_loc} = 
            $SC->org_sn_from_id($session, $copy->circ_lib);
    }

    if ($circ) {
        my $usr = $session->editor->retrieve_actor_user([
            $circ->usr, {flesh => 1, flesh_fields => {au => ['card']}}]);

        $details->{patron_barcode} = 
            $usr->card->barcode if $usr && $usr->card;
    }

    handle_hold($session, $details, $payload, %params);

    if ($textcode eq 'NO_CHANGE' || $textcode eq 'SUCCESS') {

        $details->{ok} = 1;

    } elsif ($textcode eq 'ROUTE_ITEM') {

        $details->{ok} = 1;
        $details->{alert} = 1;
        $details->{alert_type} = '04' unless $details->{alert_type};

    } else {

        $details->{ok} = 0; # unknown
        $details->{alert} = 1;
        $details->{alert_type} = '00' unless $details->{alert_type};
    }

    return 0;
}

sub handle_hold {
    my ($session, $details, $payload, %params) = @_;

    my $hold = $payload->{remote_hold} || $payload->{hold};

    return unless $hold;

    my ($pickup_lib_id, $pickup_lib_sn);

    my $holder = $session->editor->retrieve_actor_user(
        [$hold->usr, {flesh => 1, flesh_fields => {au => ['card']}}]);

    $details->{hold_patron_name} = $SC->format_user_name($holder);

    if (my $card = $holder->card) { # null-able
        $details->{hold_patron_barcode} = $card->barcode;
    }

    $details->{hold_patron_phone} = 
        $holder->day_phone || $holder->evening_phone || $holder->other_phone;

    if (ref $hold->pickup_lib) {
        $pickup_lib_id = $hold->pickup_lib->id;
        $pickup_lib_sn = $hold->pickup_lib->shortname;

    } else {
        $pickup_lib_id = $hold->pickup_lib;
        $pickup_lib_sn = $SC->org_sn_from_id($session, $pickup_lib_id);
    }

    $details->{alert} = 1;
    $details->{destination_loc} = $pickup_lib_sn;
    $details->{alert_type} = 
        ($pickup_lib_id == $session->editor->requestor->ws_ou) ? '01' : '02';
}

1;
