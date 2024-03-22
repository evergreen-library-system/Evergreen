package OpenILS::Application::SIP2::Item;
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
my $U = 'OpenILS::Application::AppUtils';
my $SC = 'OpenILS::Application::SIP2::Common';

sub get_item_details {
    my ($class, $session, %params) = @_;

    my $config = $session->config;
    my $barcode = $params{barcode};
    my $e = $session->editor;

    my $item = $e->search_asset_copy([{
        barcode => $barcode,
        deleted => 'f'
    }, {
        flesh => 3,
        flesh_fields => {
            acp => [qw/circ_lib call_number
                status stat_cat_entry_copy_maps circ_modifier/],
            acn => [qw/owning_lib record/],
            bre => [qw/flat_display_entries/],
            ascecm => [qw/stat_cat stat_cat_entry/],
        }
    }])->[0];

    return undef unless $item;

    my $details = {
        item => $item,
        call_number => $item->call_number->label,
        security_marker => '02', # matches SIP/Item.pm
        owning_loc => $item->call_number->owning_lib->shortname,
        current_loc => $item->circ_lib->shortname,
        permanent_loc => $item->circ_lib->shortname,
        destination_loc => $item->circ_lib->shortname # maybe replaced below
    };

    # use the non-translated version of the copy location as the
    # collection code, since it may be used for additional routing
    # purposes by the SIP client.  Config option?
    $details->{collection_code} = $e->retrieve_asset_copy_location(
		[$item->location, {no_i18n => 1}])->name;

    $details->{circ} = $e->search_action_circulation([{
        target_copy => $item->id,
        checkin_time => undef,
        '-or' => [
            {stop_fines => undef},
            {stop_fines => [qw/MAXFINES LONGOVERDUE/]},
        ]
    }, {
        flesh => 2,
        flesh_fields => {circ => ['usr'], au => ['card']}
    }])->[0];

    if ($details->{circ}) {

        my $due_date = DateTime::Format::ISO8601->new->
            parse_datetime(clean_ISO8601($details->{circ}->due_date));

        $details->{due_date} =
            $config->{settings}->{due_date_use_sip_date_format} ?
            $SC->sipdate($due_date) :
            $due_date->strftime('%F %T');
    }

    if ($item->status->id == OILS_COPY_STATUS_IN_TRANSIT) {
        $details->{transit} = $e->search_action_transit_copy([{
            target_copy => $item->id,
            dest_recv_time => undef,
            cancel_time => undef
        },{
            flesh => 1,
            flesh_fields => {atc => ['dest']}
        }])->[0];

        $details->{destination_loc} = $details->{transit}->dest->shortname;
    }

    if ($item->status->id == OILS_COPY_STATUS_ON_HOLDS_SHELF || (
        $details->{transit} &&
        $details->{transit}->copy_status == OILS_COPY_STATUS_ON_HOLDS_SHELF)) {

        $details->{hold} = $e->search_action_hold_request([{
            current_copy        => $item->id,
            capture_time        => {'!=' => undef},
            cancel_time         => undef,
            fulfillment_time    => undef
        }, {
            limit => 1,
            flesh => 1,
            flesh_fields => {ahr => ['pickup_lib']}
        }])->[0];
    }

    if (my $hold = $details->{hold}) {
        my $pickup_date = $hold->shelf_expire_time;
        $details->{hold_pickup_date} =
            $pickup_date ? $SC->sipdate($pickup_date) : undef;

        my $card = $e->search_actor_card({usr => $hold->usr})->[0];
        $details->{hold_patron_barcode} = $card->barcode if $card;
        $details->{destination_loc} = $hold->pickup_lib->shortname;
    }

    my ($title_entry) = grep {$_->name eq 'title'}
        @{$item->call_number->record->flat_display_entries};

    $details->{title} = $title_entry ? $title_entry->value : '';

    # Same as ../SIP*
    $details->{hold_queue_length} = $details->{hold} ? 1 : 0;

    $details->{circ_status} = circulation_status($item->status->id);

    $details->{fee_type} =
        ($item->deposit_amount > 0.0 && $item->deposit eq 'f') ?
        '06' : '01';

    my $cmod = $item->circ_modifier;
    $details->{magnetic_media} = $cmod && $cmod->magnetic_media eq 't';
    $details->{media_type} = $cmod ? $cmod->sip2_media_type : '001';

    return $details;
}

# Maps item status to SIP circulation status constants.
sub circulation_status {
    my $stat = shift;

    return '02' if $stat == OILS_COPY_STATUS_ON_ORDER;
    return '03' if $stat == OILS_COPY_STATUS_AVAILABLE;
    return '04' if $stat == OILS_COPY_STATUS_CHECKED_OUT;
    return '06' if $stat == OILS_COPY_STATUS_IN_PROCESS;
    return '08' if $stat == OILS_COPY_STATUS_ON_HOLDS_SHELF;
    return '09' if $stat == OILS_COPY_STATUS_RESHELVING;
    return '10' if $stat == OILS_COPY_STATUS_IN_TRANSIT;
    return '12' if (
        $stat == OILS_COPY_STATUS_LOST ||
        $stat == OILS_COPY_STATUS_LOST_AND_PAID
    );
    return '13' if $stat == OILS_COPY_STATUS_MISSING;

    return '01';
}

1

