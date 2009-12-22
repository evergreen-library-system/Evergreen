package OpenILS::Application::Booking;

use strict;
use warnings;

use OpenILS::Application;
use base qw/OpenILS::Application/;

use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

use OpenSRF::Utils::Logger qw/$logger/;

sub prepare_new_brt {
    my ($record_id, $owning_lib, $mvr) = @_;

    my $brt = new Fieldmapper::booking::resource_type;
    $brt->isnew(1);
    $brt->name($mvr->title);
    $brt->record($record_id);
    $brt->catalog_item('t');
    $brt->owner($owning_lib);

    return $brt;
}

sub get_existing_brt {
    my ($e, $record_id, $owning_lib, $mvr) = @_;
    my $results = $e->search_booking_resource_type(
        {name => $mvr->title, owner => $owning_lib, record => $record_id}
    );

    return $results->[0] if scalar(@$results) > 0;
    return undef;
}

sub get_mvr {
    return $U->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.mods_slim.retrieve.authoritative',
        shift # record id
    );
}

sub get_unique_owning_libs {
    my %hash = ();
    $hash{$_->call_number->owning_lib} = 1 foreach (@_);    # @_ are copies
    return keys %hash;
}

sub fetch_copies_by_ids {
    my ($e, $copy_ids) = @_;
    my $results = $e->search_asset_copy([
        {id => $copy_ids},
        {flesh => 1, flesh_fields => {acp => ['call_number']}}
    ]);
    return $results if ref($results) eq 'ARRAY';
    return [];
}

sub get_single_record_id {
    my $record_id = undef;
    foreach (@_) {  # @_ are copies
        return undef if
            (defined $record_id && $record_id != $_->call_number->record);
        $record_id = $_->call_number->record;
    }
    return $record_id;
}

# This function generates the correct json_query clause for determining
# whether two given ranges overlap.  Each range is composed of a start
# and an end point.  All four points should be the same type (could be int,
# date, time, timestamp, or perhaps other types).
#
# The first range (or the first two points) should be specified as
# literal values.  The second range (or the last two points) should be
# specified as the names of columns, the values of which in a given row
# will constitute the second range in the comparison.
#
# ALSO: PostgreSQL includes an OVERLAPS operator which provides the same
# functionality in a much more concise way, but json_query does not (yet).
sub json_query_ranges_overlap {
    +{ '-or' => [
        { '-and' => [{$_[2] => {'>=', $_[0]}}, {$_[2] => {'<',  $_[1]}}]},
        { '-and' => [{$_[3] => {'>',  $_[0]}}, {$_[3] => {'<',  $_[1]}}]},
        { '-and' => { $_[3] => {'>',  $_[0]},   $_[2] => {'<=', $_[0]}}},
        { '-and' => { $_[3] => {'>',  $_[1]},   $_[2] => {'<',  $_[1]}}},
    ]};
}

sub create_brt_and_brsrc {
    my ($self, $conn, $authtoken, $copy_ids) = @_;
    my (@created_brt, @created_brsrc);
    my %brt_table = ();

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    my @copies = @{fetch_copies_by_ids($e, $copy_ids)};
    my $record_id = get_single_record_id(@copies) or return $e->die_event;
    my $mvr = get_mvr($record_id) or return $e->die_event;

    foreach (get_unique_owning_libs(@copies)) {
        $brt_table{$_} = get_existing_brt($e, $record_id, $_, $mvr) ||
            prepare_new_brt($record_id, $_, $mvr);
    }

    while (my ($owning_lib, $brt) = each %brt_table) {
        my $pre_existing = 1;
        if ($brt->isnew) {
            if ($e->allowed('ADMIN_BOOKING_RESOURCE_TYPE', $owning_lib)) {
                $pre_existing = 0;
                return $e->die_event unless (
                    #    v-- Important: assignment modifies original hash
                    $brt = $e->create_booking_resource_type($brt)
                );
            }
        }
        push @created_brt, [$brt->id, $brt->record, $pre_existing];
    }

    foreach (@copies) {
        if ($e->allowed(
            'ADMIN_BOOKING_RESOURCE', $_->call_number->owning_lib
        )) {
            # This block needs to disregard any cstore failures and just
            # return what results it can.
            my $brsrc = new Fieldmapper::booking::resource;
            $brsrc->isnew(1);
            $brsrc->type($brt_table{$_->call_number->owning_lib}->id);
            $brsrc->owner($_->call_number->owning_lib);
            $brsrc->barcode($_->barcode);

            $e->set_savepoint("alpha");
            my $pre_existing = 0;
            my $usable_result = undef;
            if (!($usable_result = $e->create_booking_resource($brsrc))) {
                $e->rollback_savepoint("alpha");
                if (($usable_result = $e->search_booking_resource(
                    +{ map { ($_, $brsrc->$_()) } qw/type owner barcode/ }
                ))) {
                    $usable_result = $usable_result->[0];
                    $pre_existing = 1;
                } else {
                    # So we failed to create a booking resource for this copy.
                    # For now, let's just keep going.  If the calling app wants
                    # to consider this an error, it can notice the absence
                    # of a booking resource for the copy in the returned
                    # results.
                    $logger->warn(
                        "Couldn't create or find brsrc for acp #" .  $_->id
                    );
                }
            } else {
                $e->release_savepoint("alpha");
            }

            if ($usable_result) {
                push @created_brsrc,
                    [$usable_result->id, $_->id, $pre_existing];
            }
        }
    }

    $e->commit and
        return {brt => \@created_brt, brsrc => \@created_brsrc} or
        return $e->die_event;
}
__PACKAGE__->register_method(
    method   => "create_brt_and_brsrc",
    api_name => "open-ils.booking.resources.create_from_copies",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'array', desc => 'Copy IDs'},
        ],
        return => { desc => "A two-element hash. The 'brt' element " .
            "is a list of created booking resource types described by " .
            "3-tuples (id, copy id, was pre-existing).  The 'brsrc' " .
            "element is a similar list of created booking resources " .
            "described by (id, record id, was pre-existing) 3-tuples."}
    }
);


sub create_bresv {
    my ($self, $client, $authtoken,
        $target_user_barcode, $datetime_range,
        $brt, $brsrc_list, $attr_values) = @_;

    $brsrc_list = [ undef ] if not defined $brsrc_list;
    return undef if scalar(@$brsrc_list) < 1; # Empty list not ok.

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless (
        $e->checkauth and
        $e->allowed("ADMIN_BOOKING_RESERVATION") and
        $e->allowed("ADMIN_BOOKING_RESERVATION_ATTR_MAP")
    );

    my $usr = $U->fetch_user_by_barcode($target_user_barcode);
    return $usr if ref($usr) eq 'HASH' and exists($usr->{"ilsevent"});

    my $results = [];
    foreach my $brsrc (@$brsrc_list) {
        my $bresv = new Fieldmapper::booking::reservation;
        $bresv->usr($usr->id);
        $bresv->request_lib($e->requestor->ws_ou);
        $bresv->pickup_lib($e->requestor->ws_ou);
        $bresv->start_time($datetime_range->[0]);
        $bresv->end_time($datetime_range->[1]);

        # A little sanity checking: don't agree to put a reservation on a
        # brsrc and a brt when they don't match.  In fact, bomb out of
        # this transaction entirely.
        if ($brsrc) {
            my $brsrc_itself = $e->retrieve_booking_resource($brsrc) or
                return $e->die_event;
            return $e->die_event if ($brsrc_itself->type != $brt);
        }
        $bresv->target_resource($brsrc);    # undef is ok here
        $bresv->target_resource_type($brt);

        ($bresv = $e->create_booking_reservation($bresv)) or
            return $e->die_event;

        # We could/should do some sanity checking on this too: namely, on
        # whether the attribute values given actually apply to the relevant
        # brt.  Not seeing any grievous side effects of not checking, though.
        my @bravm = ();
        foreach my $value (@$attr_values) {
            my $bravm = new Fieldmapper::booking::reservation_attr_value_map;
            $bravm->reservation($bresv->id);
            $bravm->attr_value($value);
            $bravm = $e->create_booking_reservation_attr_value_map($bravm) or
                return $e->die_event;
            push @bravm, $bravm;
        }
        push @$results, {
            "bresv" => $bresv->id,
            "bravm" => \@bravm,
        };
    }

    $e->commit or return $e->die_event;

    # Targeting must be tacked on _after_ committing the transaction where the
    # reservations are actually created.
    foreach (@$results) {
        $_->{"targeting"} = $U->storagereq(
            "open-ils.storage.booking.reservation.resource_targeter",
            $_->{"bresv"}
        )->[0];
    }
    return $results;
}
__PACKAGE__->register_method(
    method   => "create_bresv",
    api_name => "open-ils.booking.reservations.create",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'string', desc => 'Barcode of user for whom to reserve'},
            {type => 'array', desc => 'Two elements: start and end timestamp'},
            {type => 'int', desc => 'Booking resource type'},
            {type => 'list', desc => 'Booking resource (undef ok; empty not ok)'},
            {type => 'array', desc => 'Attribute values selected'},
        ],
        return => { desc => "A hash containing the new bresv and a list " .
            "of new bravm"}
    }
);


sub resource_list_by_attrs {
    my $self = shift;
    my $client = shift;
    my $auth = shift; # Keep as argument, though not used just now.
    my $filters = shift;

    return undef unless ($filters->{type} || $filters->{attribute_values});

    my $query = {
        'select'   => { brsrc => [ 'id' ] },
        'from'     => { brsrc => {} },
        'where'    => {},
        'distinct' => 1
    };

    $query->{where} = {"-and" => []};
    if ($filters->{type}) {
        push @{$query->{where}->{"-and"}}, {"type" => $filters->{type}};
    }

    if ($filters->{attribute_values}) {

        $query->{from}->{brsrc}->{bram} = { field => 'resource' };

        $filters->{attribute_values} = [$filters->{attribute_values}]
            if (!ref($filters->{attribute_values}));

        $query->{having}->{'+bram'}->{value}->{'@>'} = {
            transform => 'array_accum',
            value => '$_' . $$ . '${' .
                join(',', @{$filters->{attribute_values}}) .
                '}$_' . $$ . '$'
        };
    }

    if ($filters->{available}) {
        # If only one timestamp has been provided, make it into a range.
        if (!ref($filters->{available})) {
            $filters->{available} = [($filters->{available}) x 2];
        }

        push @{$query->{where}->{"-and"}}, {
            "-or" => [
                {"overbook" => "t"},
                {"-not-exists" => {
                    "select" => {"bresv" => ["id"]},
                    "from" => "bresv",
                    "where" => {"-and" => [
                        json_query_ranges_overlap(
                            $filters->{available}->[0],
                            $filters->{available}->[1],
                            "start_time",
                            "end_time"
                        ),
                        {"cancel_time" => undef},
                        {"current_resource" => {"=" => {"+brsrc" => "id"}}}
                    ]},
                }}
            ]
        };
    }
    if ($filters->{booked}) {
        # If only one timestamp has been provided, make it into a range.
        if (!ref($filters->{booked})) {
            $filters->{booked} = [($filters->{booked}) x 2];
        }

        push @{$query->{where}->{"-and"}}, {
            "-exists" => {
                "select" => {"bresv" => ["id"]},
                "from" => "bresv",
                "where" => {"-and" => [
                    json_query_ranges_overlap(
                        $filters->{booked}->[0],
                        $filters->{booked}->[1],
                        "start_time",
                        "end_time"
                    ),
                    {"cancel_time" => undef},
                    {"current_resource" => { "=" => {"+brsrc" => "id"}}}
                ]},
            }
        };
        # I think that the "booked" case could be done with a JOIN instead of
        # an EXISTS, but I'm leaving it this way for symmetry with the
        # "available" case for now.  The available case cannot be done with a
        # join.
    }

    my $cstore = OpenSRF::AppSession->connect('open-ils.cstore');
    my $rows = $cstore->request( 'open-ils.cstore.json_query.atomic', $query )->gather(1);
    $cstore->disconnect;

    return @$rows ? [map { $_->{id} } @$rows] : [];
}
__PACKAGE__->register_method(
    method   => "resource_list_by_attrs",
    api_name => "open-ils.booking.resources.filtered_id_list",
    argc     => 3,
    signature=> {
        params => [
            {type => 'string', desc => 'Authentication token (unused for now,' .
               ' but at least pass undef here)'},
            {type => 'object', desc => 'Filter object: see notes for details'},
            {type => 'bool', desc => 'Return whole objects instead of IDs?'}
        ],
        return => { desc => "An array of brsrc ids matching the requested filters." },
    },
    notes    => <<'NOTES'

The filter object parameter can contain the following keys:
 * type             => The id of a booking resource type (brt)
 * attribute_values => The ids of booking resource type attribute values that the resource must have assigned to it (brav)
 * available        => Either:
                        A timestamp during which the resources are not reserved.  If the resource is overbookable, this is ignored.
                        A range of two timestamps which do not overlap any reservations for the resources.  If the resource is overbookable, this is ignored.
 * booked           => Either:
                        A timestamp during which the resources are reserved.
                        A range of two timestamps which overlap a reservation of the resources.

Note that at least one of 'type' or 'attribute_values' is required.

NOTES
);


sub reservation_list_by_filters {
    my $self = shift;
    my $client = shift;
    my $auth = shift;
    my $filters = shift;
    my $whole_obj = shift;

    return undef unless ($filters->{user} || $filters->{user_barcode} || $filters->{resource} || $filters->{type} || $filters->{attribute_values});

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_TRANSACTION');

    my $query = {
        'select'   => { bresv => [ 'id', 'start_time' ] },
        'from'     => { bresv => {} },
        'where'    => {},
        'order_by' => [{ class => bresv => field => start_time => direction => 'asc' }],
        'distinct' => 1
    };

    if ($filters->{fields}) {
        $query->{where} = $filters->{fields};
    }


    if ($filters->{user}) {
        $query->{where}->{usr} = $filters->{user};
    }
    elsif ($filters->{user_barcode}) {  # just one of user and user_barcode
        my $usr = $U->fetch_user_by_barcode($filters->{user_barcode});
        return $usr if ref($usr) eq 'HASH' and exists($usr->{"ilsevent"});
        $query->{where}->{usr} = $usr->id;
    }


    if ($filters->{type}) {
        $query->{where}->{target_resource_type} = $filters->{type};
    }

    if ($filters->{resource}) {
        $query->{where}->{target_resource} = $filters->{resource};
    }

    if ($filters->{attribute_values}) {

        $query->{from}->{bresv}->{bravm} = { field => 'reservation' };

        $filters->{attribute_values} = [$filters->{attribute_values}]
            if (!ref($filters->{attribute_values}));

        $query->{having}->{'+bravm'}->{attr_value}->{'@>'} = {
            transform => 'array_accum',
            value => '$_' . $$ . '${' .
                join(',', @{$filters->{attribute_values}}) .
                '}$_' . $$ . '$'
        };
    }

    if ($filters->{search_start} || $filters->{search_end}) {
        $query->{where}->{'-or'} = {};

        $query->{where}->{'-or'}->{start_time} = { 'between' => [ $filters->{search_start}, $filters->{search_end} ] }
                if ($filters->{search_start});

        $query->{where}->{'-or'}->{end_time} = { 'between' => [ $filters->{search_start}, $filters->{search_end} ] }
                if ($filters->{search_end});
    }

    my $cstore = OpenSRF::AppSession->connect('open-ils.cstore');
    my $ids = [ map { $_->{id} } @{
        $cstore->request(
            'open-ils.cstore.json_query.atomic', $query
        )->gather(1)
    } ];
    $cstore->disconnect;

    return $ids if not $whole_obj;

    my $bresv_list = $e->search_booking_reservation([
        {"id" => $ids},
        {"flesh" => 1,
            "flesh_fields" => {
                "bresv" =>
                    [qw/target_resource current_resource target_resource_type/]
            }
        }]
    );
    return $bresv_list ? $bresv_list : [];
}
__PACKAGE__->register_method(
    method   => "reservation_list_by_filters",
    api_name => "open-ils.booking.reservations.filtered_id_list",
    argc     => 2,
    signature=> {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'object', desc => 'Filter object -- see notes for details'}
        ],
        return => { desc => "An array of bresv ids matching the requested filters." },
    },
    notes    => <<'NOTES'

The filter object parameter can contain the following keys:
 * user             => The id of a user that has requested a bookable item -- filters on bresv.usr
 * barcode          => The barcode of a user that has requested a bookable item
 * type             => The id of a booking resource type (brt) -- filters on bresv.target_resource_type
 * resource         => The id of a booking resource (brsrc) -- filters on bresv.target_resource
 * attribute_values => The ids of booking resource type attribute values that the resource must have assigned to it (brav)
 * search_start     => If search_end is not specified, booking interval (start_time to end_time) must contain this timestamp.
 * search_end       => If search_start is not specified, booking interval (start_time to end_time) must contain this timestamp.
 * fields           => An object containing any combination of bresv search filters in standard cstore/pcrud search format.

Note that at least one of 'user', 'type', 'resource' or 'attribute_values' is required.  If both search_start and search_end are specified,
then the result includes any reservations that overlap with that time range.  Any filter fields supplied in 'fields' are overridden
by the top-level filters ('user', 'type', 'resource').

NOTES
);

sub capture_reservation {
    my $self = shift;
    my $client = shift;
    my $auth = shift;
    my $res_id = shift;

    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('CAPTURE_RESERVATION');
    my $here = $e->requestor->ws_ou;

    my $reservation = $e->retrieve_booking_reservation( $res_id );
    return OpenILS::Event->new('RESERVATION_NOT_FOUND') unless $reservation;

    return OpenILS::Event->new('RESERVATION_CAPTURE_FAILED', payload => { captured => 0, fail_cause => 'no-resource' })
        if (!$reservation->current_resource); # no resource

    return OpenILS::Event->new('RESERVATION_CAPTURE_FAILED', payload => { captured => 0, fail_cause => 'cancelled' })
        if ($reservation->cancel_time); # canceled

    my $resource = $e->retrieve_booking_resource( $reservation->current_resource );
    my $type = $e->retrieve_booking_resource( $resource->type );

    $reservation->capture_staff( $e->requestor->id );
    $reservation->capture_time( 'now' );

    return $e->event unless ( $e->update_booking_reservation( $reservation ) and $reservation = $e->data );

    my $ret = { captured => 1, reservation => $reservation };

    if ($here <> $reservation->pickup_lib) {
        return OpenILS::Event->new('RESERVATION_CAPTURE_FAILED', payload => { captured => 0, fail_cause => 'not-transferable' })
            if (!$U->is_true($type->transferable)); # non-transferable resource

        # need to transit the item ... is it already in transit?
        my $transit = $e->search_action_reservation_transit_copy( { reservation => $res_id, dest_recv_time => undef } )->[0];

        if (!$transit) { # not yet in transit
            $transit = new Fieldmapper::action::reservation_transit_copy ();

            $transit->copy($resource->id);
            $transit->copy_status(15);
            $transit->source_send_time('now');
            $transit->source($here);
            $transit->dest($reservation->pickup_lib);

            $e->create_action_reservation_transit_copy( $transit );

            if ($U->is_true($type->catalog_item)) {
                my $copy = $e->search_asset_copy( { barcode => $resource->barcode, deleted => 'f' } )->[0];

                if ($copy) {
                    return OpenILS::Event->new('OPEN_CIRCULATION_EXISTS', payload => $copy) if ($copy->status == 1);
                    $copy->status(6);
                    $e->update_asset_copy( $copy );
                    $$ret{catalog_item} = $e->data;
                }
            }
        }

        $$ret{transit} = $transit;
    } elsif ($U->is_true($type->catalog_item)) {
        my $copy = $e->search_asset_copy( { barcode => $resource->barcode, deleted => 'f' } )->[0];

        if ($copy) {
            return OpenILS::Event->new('OPEN_CIRCULATION_EXISTS', payload => { captured => 0, copy => $copy }) if ($copy->status == 1);
            $copy->status(15);
            $e->update_asset_copy( $copy );
            $$ret{catalog_item} = $e->data;
        }
    }

    $e->commit;

    return OpenILS::Event->new('SUCCESS', payload => $ret);
}
__PACKAGE__->register_method(
    method   => "capture_reservation",
    api_name => "open-ils.booking.reservation.capture",
    argc     => 2,
    signature=> {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Reservation ID'}
        ],
        return => { desc => "An OpenILS Event object describing the outcome of the capture, with relevant payload." },
    }
);


1;
