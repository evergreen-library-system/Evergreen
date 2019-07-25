package OpenILS::Application::Booking;

use strict;
use warnings;

use POSIX qw/strftime/;
use OpenILS::Application;
use base qw/OpenILS::Application/;

use OpenILS::Utils::DateTime qw/:datetime/;
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
    $brt->transferable('t');
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
        $target_user_barcode, $datetime_range, $pickup_lib,
        $brt, $brsrc_list, $attr_values, $email_notify, $note) = @_;

    $brsrc_list = [ undef ] if not defined $brsrc_list;
    return undef if scalar(@$brsrc_list) < 1; # Empty list not ok.

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("ADMIN_BOOKING_RESERVATION");

    my $usr = $U->fetch_user_by_barcode($target_user_barcode);
    return $usr if ref($usr) eq 'HASH' and exists($usr->{"ilsevent"});

    my $results = [];
    foreach my $brsrc (@$brsrc_list) {
        my $bresv = new Fieldmapper::booking::reservation;
        $bresv->usr($usr->id);
        $bresv->request_lib($e->requestor->ws_ou);
        $bresv->pickup_lib($pickup_lib);
        $bresv->start_time($datetime_range->[0]);
        $bresv->end_time($datetime_range->[1]);
        $bresv->email_notify(1) if $email_notify;
        $bresv->note($note) if $note;

        # A little sanity checking: don't agree to put a reservation on a
        # brsrc and a brt when they don't match.  In fact, bomb out of
        # this transaction entirely.
        if ($brsrc) {
            my $brsrc_itself = $e->retrieve_booking_resource([
                $brsrc, {
                    "flesh" => 1,
                    "flesh_fields" => {"brsrc" => ["type"]}
                }
            ]);

            if (not $brsrc_itself) {
                my $ev = new OpenILS::Event(
                    "RESERVATION_BAD_PARAMS",
                    desc => "brsrc $brsrc doesn't exist"
                );
                $e->disconnect;
                return $ev;
            }
            elsif ($brsrc_itself->type->id != $brt) {
                my $ev = new OpenILS::Event(
                    "RESERVATION_BAD_PARAMS",
                    desc => "brsrc $brsrc doesn't match given brt $brt"
                );
                $e->disconnect;
                return $ev;
            }

            # Also bail if the user is trying to create a reservation at
            # a pickup lib to which our resource won't go.
            if (
                $brsrc_itself->owner != $pickup_lib and
                    not $brsrc_itself->type->transferable
            ) {
                my $ev = new OpenILS::Event(
                    "RESERVATION_BAD_PARAMS",
                    desc => "brsrc $brsrc doesn't belong to $pickup_lib and " .
                        "is not transferable"
                );
                $e->disconnect;
                return $ev;
            }
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
            {type => 'int', desc => 'Desired reservation pickup lib'},
            {type => 'int', desc => 'Booking resource type'},
            {type => 'list', desc => 'Booking resource (undef ok; empty not ok)'},
            {type => 'array', desc => 'Attribute values selected'},
            {type => 'bool', desc => 'Email notification?'},
            {type => 'string', desc => 'Optional note'},
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
        "select"   => {brsrc => [qw/id owner/], brt => ["elbow_room"]},
        "from"     => {brsrc => {"brt" => {}}},
        "where"    => {},
        "distinct" => 1
    };

    $query->{where} = {"-and" => []};
    if ($filters->{type}) {
        push @{$query->{where}->{"-and"}}, {"type" => $filters->{type}};
    }

    if ($filters->{pickup_lib}) {
        push @{$query->{where}->{"-and"}},
            {"-or" => [
                {"owner" => $filters->{pickup_lib}},
                {"+brt" => {"transferable" => "t"}}
            ]};
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
                        {"return_time" => undef},
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
    my $rows = $cstore->request(
        "open-ils.cstore.json_query.atomic", $query
    )->gather(1);
    $cstore->disconnect;

    return [] if not @$rows;

    if ($filters->{"pickup_lib"} && $filters->{"available"}) {
        my @new_rows = ();
        my $general_elbow_room = $U->ou_ancestor_setting_value(
            $filters->{"pickup_lib"},
            "circ.booking_reservation.default_elbow_room"
        ) || '0 seconds';
        my $would_start = $filters->{"available"}->[0];
        my $dt_parser = new DateTime::Format::ISO8601;

        $logger->info(
            "general_elbow_room: '$general_elbow_room', " .
            "would_start: '$would_start'"
        );

        # Here, elbow_room will double as required transit time padding.
        foreach (@$rows) {
            my $elbow_room = $_->{"elbow_room"} || $general_elbow_room;
            if ($_->{"owner"} != $filters->{"pickup_lib"}) {
                (my $ws = $would_start) =~ s/ /T/;
                push @new_rows, $_ if DateTime->compare(
                    $dt_parser->parse_datetime($ws),
                    DateTime->now(
                        "time_zone" => DateTime::TimeZone->new(
                            "name" => "local"
                        )
                    )->add(seconds => interval_to_seconds($elbow_room))
                ) >= 0;
            } else {
                push @new_rows, $_;
            }
        }
        return [map { $_->{id} } @new_rows];
    } else {
        return [map { $_->{id} } @$rows];
    }
}


__PACKAGE__->register_method(
    method   => "resource_list_by_attrs",
    api_name => "open-ils.booking.resources.filtered_id_list",
    argc     => 2,
    signature=> {
        params => [
            {type => 'string', desc => 'Authentication token (unused for now,' .
               ' but at least pass undef here)'},
            {type => 'object', desc => 'Filter object: see notes for details'},
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

    return undef unless (
           $filters->{user}
        || $filters->{user_barcode}
        || $filters->{resource}
        || $filters->{type}
        || $filters->{attribute_values}
    );

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

    $query->{where}->{"-and"} = [];
    if ($filters->{resource}) {
#       $query->{where}->{target_resource} = $filters->{resource};
        push @{$query->{where}->{"-and"}}, {
            "-or" => {
                "target_resource" => $filters->{resource},
                "current_resource" => $filters->{resource}
            }
        };
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
        my $or = {};

        $or->{start_time} =
            {'between' => [ $filters->{search_start}, $filters->{search_end}]}
                if $filters->{search_start};

        $or->{end_time} =
            {'between' =>[$filters->{search_start}, $filters->{search_end}]}
                if $filters->{search_end};

        push @{$query->{where}->{"-and"}}, {"-or" => $or};
    }

    if (not scalar @{$query->{"where"}->{"-and"}}) {
        delete $query->{"where"}->{"-and"};
    }

    my $cstore = OpenSRF::AppSession->connect('open-ils.cstore');
    my $ids = [ map { $_->{id} } @{
        $cstore->request(
            'open-ils.cstore.json_query.atomic', $query
        )->gather(1)
    } ];
    $cstore->disconnect;

    if (not $whole_obj or @$ids < 1) {
        $e->disconnect;
        return $ids;
    }

    my $bresv_list = $e->search_booking_reservation([
        {"id" => $ids},
        {"flesh" => 1,
            "flesh_fields" => {
                "bresv" =>
                    [qw/target_resource current_resource target_resource_type/]
            }
        }]
    );
    $e->disconnect;
    return $bresv_list ? $bresv_list : [];
}

__PACKAGE__->register_method(
    method   => "upcoming_reservation_list_by_user",
    api_name => "open-ils.booking.reservations.upcoming_reservation_list_by_user",
    argc     => 2,
    signature=> {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'User ID', type => 'number', desc => 'User ID'},
        ],
        return => { desc => "Information about all reservations for a user that haven't yet ended." },
    },
    notes    => "You can send undef/NULL as the User ID to get reservations for the logged in user."
);

sub upcoming_reservation_list_by_user {
    my ($self, $conn, $auth, $user_id) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    $user_id = $e->requestor->id unless defined $user_id;
    
    unless($e->requestor->id == $user_id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->event;
        return $e->event unless $e->allowed('VIEW_TRANSACTION');
    }

    my $select = { 'bresv' => [qw/start_time end_time cancel_time capture_time pickup_time pickup_lib/],
        'brsrc' => [ 'barcode' ],
        'brt' => [{'column' => 'name', 'alias' => 'resource_type_name'}],
        'aou' => ['shortname', {'column' => 'name', 'alias' => 'pickup_name'}] };

    my $from = { 'bresv' => {'brsrc' => {'field' => 'id', 'fkey' => 'current_resource'},
        'brt' => {'field' => 'id', 'fkey' => 'target_resource_type'},
        'aou' => {'field' => 'id', 'fkey' => 'pickup_lib'}} };

    my $query = {
        'select'   => $select,
        'from'     => $from,
        'where'    => { 'usr' => $user_id, 'return_time' => undef, 'end_time' => {'>' => gmtime_ISO8601() }},
        'order_by' => [{ class => bresv => field => start_time => direction => 'asc' }]
    };

    my $cstore = OpenSRF::AppSession->connect('open-ils.cstore');
    my $rows = $cstore->request(
        'open-ils.cstore.json_query.atomic', $query
    )->gather(1);
    $cstore->disconnect;
    $e->disconnect;
    return [] if not @$rows;
    return $rows;
}

__PACKAGE__->register_method(
    method   => "reservation_list_by_filters",
    api_name => "open-ils.booking.reservations.filtered_id_list",
    argc     => 3,
    signature=> {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => "object", desc => "Filter object: see notes for details"},
            {type => "bool", desc => "Return whole object instead of ID? (default false)"}
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


sub naive_ts_string {strftime("%F %T", localtime($_[0] || time));}

# Return a map of bresv or an ilsevent on failure.
sub get_uncaptured_bresv_for_brsrc {
    my ($e, $o) = @_; # o's keys (all optional): owning_lib, barcode, range

    my $from_clause = {
        "bresv" => {
            "brsrc" => {"field" => "id", "fkey" => "current_resource"}
        }
    };

    my $query = {
        "select" => {
            "bresv" => [
                "current_resource",
                {
                    "column" => "start_time",
                    "transform" => "min",
                    "aggregate" => 1
                }
            ]
        },
        "from" => $from_clause,
        "where" => {
            "-and" => [
                {"current_resource" => {"!=" => undef}},
                {"capture_time" => undef},
                {"cancel_time" => undef},
                {"return_time" => undef},
                {"pickup_time" => undef}
            ]
        }
    };
    if ($o->{"owning_lib"}) {
        push @{$query->{"where"}->{"-and"}},
            {"+brsrc" => {"owner" => $o->{"owning_lib"}}};
    }
    if ($o->{"range"}) {
        push @{$query->{"where"}->{"-and"}},
            json_query_ranges_overlap(
                $o->{"range"}->[0], $o->{"range"}->[1],
                "start_time", "end_time"
            );
    }
    if ($o->{"barcode"}) {
        push @{$query->{"where"}->{"-and"}},
            {"+brsrc" => {"barcode" => $o->{"barcode"}}};
    }

    my $rows = $e->json_query($query);
    my $current_resource_bresv_map = {};
    if (@$rows) {
        my $id_query = {
            "select" => {"bresv" => ["id"]},
            "from" => $from_clause,
            "where" => {
                "-and" => [
                    {"current_resource" => "PLACEHOLDER"},
                    {"start_time" => "PLACEHOLDER"},
                    {"capture_time" => undef},
                    {"cancel_time" => undef},
                    {"return_time" => undef},
                    {"pickup_time" => undef}
                ]
            }
        };
        if ($o->{"owning_lib"}) {
            push @{$id_query->{"where"}->{"-and"}},
                {"+brsrc" => {"owner" => $o->{"owning_lib"}}};
        }

        foreach (@$rows) {
            $id_query->{"where"}->{"-and"}->[0]->{"current_resource"} =
                $_->{"current_resource"};
            $id_query->{"where"}->{"-and"}->[1]->{"start_time"} =
                $_->{"start_time"};

            my $results = $e->json_query($id_query);
            if ($results && @$results) {
                $current_resource_bresv_map->{$_->{"current_resource"}} =
                    [map { $_->{"id"} } @$results];
            }
        }
    }
    return $current_resource_bresv_map;
}

sub get_pull_list {
    my ($self, $client, $auth, $range, $interval_secs, $owning_lib) = @_;

    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("RETRIEVE_RESERVATION_PULL_LIST");
    return $e->die_event unless (
        ref($range) eq "ARRAY" or
        ($interval_secs = int($interval_secs)) > 0
    );

    $owning_lib = $e->requestor->ws_ou if not $owning_lib;
    $range = [ naive_ts_string(time), naive_ts_string(time + $interval_secs) ]
        if not $range;

    my $uncaptured = get_uncaptured_bresv_for_brsrc(
        $e, {"range" => $range, "owning_lib" => $owning_lib}
    );

    if (keys(%$uncaptured)) {
        my @all_bresv_ids = map { @{$_} } values %$uncaptured;
        my %bresv_lookup = (
            map { $_->id => $_ } @{
                $e->search_booking_reservation([{"id" => [@all_bresv_ids]}, {
                    flesh => 1,
                    flesh_fields => { bresv => [
                        "usr", "target_resource_type", "current_resource"
                    ]}
                }])
            }
        );
        $e->disconnect;
        return [ map {
            my $key = $_;
            my $one = $bresv_lookup{$uncaptured->{$key}->[0]};
            my $result = {
                "current_resource" => $one->current_resource,
                "target_resource_type" => $one->target_resource_type,
                "reservations" => [
                    map { $bresv_lookup{$_} } @{$uncaptured->{$key}}
                ]
            };
            foreach (@{$result->{"reservations"}}) {    # deflesh
                $_->current_resource($_->current_resource->id);
                $_->target_resource_type($_->target_resource_type->id);
            }
            $result;
        } keys %$uncaptured ];
    } else {
        $e->disconnect;
        return [];
    }
}
__PACKAGE__->register_method(
    method   => "get_pull_list",
    api_name => "open-ils.booking.reservations.get_pull_list",
    argc     => 4,
    signature=> {
        params => [
            {type => "string", desc => "Authentication token"},
            {type => "array", desc =>
                "range: Date/time range for reservations (opt)"},
            {type => "int", desc =>
                "interval: Seconds from now (instead of range)"},
            {type => "number", desc => "(Optional) Owning library"}
        ],
        return => { desc => "An array of hashes, each containing key/value " .
            "pairs describing resource, resource type, and a list of " .
            "reservations that claim the given resource." }
    }
);


sub could_capture {
    my ($self, $client, $auth, $barcode) = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("COPY_CHECKIN");

    my $dt_parser = new DateTime::Format::ISO8601;
    my $now = now DateTime; # sic
    my $res = get_uncaptured_bresv_for_brsrc($e, {"barcode" => $barcode});

    if ($res and keys %$res) {
        my $id;
        while ((undef, $id) = each %$res) {
            my $bresv = $e->retrieve_booking_reservation([
                $id, {
                    "flesh" => 1, "flesh_fields" => {
                        "bresv" => [qw(
                            usr target_resource_type
                            target_resource current_resource
                        )]
                    }
                }
            ]);
            my $elbow_room = interval_to_seconds(
                $bresv->target_resource_type->elbow_room ||
                $U->ou_ancestor_setting_value(
                    $bresv->pickup_lib,
                    "circ.booking_reservation.default_elbow_room"
                ) ||
                "0 seconds"
            );

            unless ($elbow_room) {
                $client->respond($bresv);
            } else {
                my $start_time = $dt_parser->parse_datetime(
                    clean_ISO8601($bresv->start_time)
                );

                if ($now >= $start_time->subtract("seconds" => $elbow_room)) {
                    $client->respond($bresv);
                } else {
                    $logger->info(
                        "not within elbow room: $elbow_room, " .
                        "else would have returned bresv " . $bresv->id
                    );
                }
            }
        }
    }
    $e->disconnect;
    undef;
}
__PACKAGE__->register_method(
    method   => "could_capture",
    api_name => "open-ils.booking.reservations.could_capture",
    argc     => 2,
    streaming=> 1,
    signature=> {
        params => [
            {type => "string", desc => "Authentication token"},
            {type => "string", desc => "Resource barcode"}
        ],
        return => {desc => "One or zero reservations; event on error."}
    }
);


sub get_copy_fleshed_just_right {
    my ($self, $client, $auth, $barcode) = @_;

    return undef if not defined $barcode;
    return {} if ref($barcode) eq "ARRAY" and not @$barcode;

    my $e = new_editor(authtoken => $auth);
    my $results = $e->search_asset_copy([
        {"barcode" => $barcode},
        {
            "flesh" => 1,
            "flesh_fields" => {"acp" => [qw/call_number location/]}
        }
    ]);

    if (ref($results) eq "ARRAY") {
        $e->disconnect;
        return $results->[0] unless ref $barcode;
        return +{ map { $_->barcode => $_ } @$results };
    } else {
        return $e->die_event;
    }
}
__PACKAGE__->register_method(
    method   => "get_copy_fleshed_just_right",
    api_name => "open-ils.booking.asset.get_copy_fleshed_just_right",
    argc     => 2,
    signature=> {
        params => [
            {type => "string", desc => "Authentication token"},
            {type => "mixed", desc => "One barcode or an array of them"},
        ],
        return => { desc =>
            "A copy, or a hash of copies keyed by barcode if an array of " .
            "barcodes was given"
        }
    }
);


sub best_bresv_candidate {
    my ($e, $id_list) = @_;

    # This will almost always be the case.
    if (@$id_list == 1) {
        $logger->info("best_bresv_candidate (only) " . $id_list->[0]);
        return $id_list->[0];
    }

    my @here = ();
    my $this_ou = $e->requestor->ws_ou;
    my $results = $e->json_query({
        "select" => {"brsrc" => ["pickup_lib"], "bresv" => ["id"]},
        "from" => {
            "bresv" => {
                "brsrc" => {"field" => "id", "fkey" => "current_resource"}
            }
        },
        "where" => {
            {"+bresv" => {"id" => $id_list}}
        }
    });

    foreach (@$results) {
        push @here, $_->{"id"} if $_->{"pickup_lib"} == $this_ou;
    }

    my $result;
    if (@here > 0) {
        $result = @here == 1 ? pop @here : (sort @here)[0];
    } else {
        $result = (sort @$id_list)[0];
    }
    $logger->info(
        "best_bresv_candidate from " . join(",", @$id_list) . ": $result"
    );
    return $result;
}


sub capture_resource_for_reservation {
    my ($self, $client, $auth, $barcode, $no_update_copy) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("COPY_CHECKIN");

    my $uncaptured = get_uncaptured_bresv_for_brsrc(
        $e, {"barcode" => $barcode}
    );

    if (keys %$uncaptured) {
        # Note this will only capture one reservation at a time, even in
        # cases with overbooking (multiple "soonest" bresv's on a resource).
        my $bresv = best_bresv_candidate(
            $e, $uncaptured->{
                (sort(keys %$uncaptured))[0]
            }
        );
        $e->disconnect;
        return capture_reservation(
            $self, $client, $auth, $bresv, $no_update_copy
        );
    } else {
        return new OpenILS::Event(
            "RESERVATION_NOT_FOUND",
            "desc" => "No capturable reservation found pertaining " .
                "to a resource with barcode $barcode",
            "payload" => {"fail_cause" => "no-reservation", "captured" => 0}
        );
    }
}
__PACKAGE__->register_method(
    method   => "capture_resource_for_reservation",
    api_name => "open-ils.booking.resources.capture_for_reservation",
    argc     => 3,
    signature=> {
        params => [
            {type => "string", desc => "Authentication token"},
            {type => "string", desc => "Barcode of booked & targeted resource"},
            {type => "number", desc => "(optional) 1 to not update copy"}
        ],
        return => { desc => "An OpenILS event describing the capture outcome" }
    }
);


sub capture_reservation {
    my ($self, $client, $auth, $res_id, $no_update_copy) = @_;

    my $e = new_editor("xact" => 1, "authtoken" => $auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("COPY_CHECKIN");
    my $here = $e->requestor->ws_ou;

    my $reservation = $e->retrieve_booking_reservation([
        $res_id, {
            "flesh" => 2, "flesh_fields" => {
                "bresv" => [qw/usr current_resource type/],
                "au" => ["card"],
                "brsrc" => ["type"]
            }
        }
    ]);

    return new OpenILS::Event("RESERVATION_NOT_FOUND") unless $reservation;
    return new OpenILS::Event(
        "RESERVATION_CAPTURE_FAILED",
        payload => {"captured" => 0, "fail_cause" => "no-resource"}
    ) unless $reservation->current_resource;

    return new OpenILS::Event(
        "RESERVATION_CAPTURE_FAILED",
        "payload" => {"captured" => 0, "fail_cause" => "cancelled"}
    ) if $reservation->cancel_time;

    $reservation->capture_staff($e->requestor->id);
    $reservation->capture_time("now");

    $e->update_booking_reservation($reservation) or return $e->die_event;

    my $ret = {"captured" => 1, "reservation" => $reservation};

    my $search_acp_like_this = [
        {
            "barcode" => $reservation->current_resource->barcode,
            "deleted" => "f"
        },
        {"flesh" => 1, "flesh_fields" => {"acp" => ["call_number"]}}
    ];

    if ($here != $reservation->pickup_lib) {
        $logger->info("resource isn't at the reservation's pickup lib...");
        return new OpenILS::Event(
            "RESERVATION_CAPTURE_FAILED",
            "payload" => {"captured" => 0, "fail_cause" => "not-transferable"}
        ) unless $U->is_true(
            $reservation->current_resource->type->transferable
        );

        # need to transit the item ... is it already in transit?
        my $transit = $e->search_action_reservation_transit_copy(
            {"reservation" => $res_id, "dest_recv_time" => undef, cancel_time => undef}
        )->[0];

        if (!$transit) { # not yet in transit
            $transit = new Fieldmapper::action::reservation_transit_copy;

            $transit->reservation($reservation->id);
            $transit->target_copy($reservation->current_resource->id);
            $transit->copy_status(15);
            $transit->source_send_time("now");
            $transit->source($here);
            $transit->dest($reservation->pickup_lib);

            $e->create_action_reservation_transit_copy($transit);

            if ($U->is_true(
                $reservation->current_resource->type->catalog_item
            )) {
                my $copy = $e->search_asset_copy($search_acp_like_this)->[0];

                if ($copy) {
                    return new OpenILS::Event(
                        "OPEN_CIRCULATION_EXISTS",
                        "payload" => {"captured" => 0, "copy" => $copy}
                    ) if $copy->status == 1 and not $no_update_copy;

                    $ret->{"mvr"} = get_mvr($copy->call_number->record);
                    if ($no_update_copy) {
                        $ret->{"new_copy_status"} = 6;
                    } else {
                        $copy->status(6);
                        $e->update_asset_copy($copy) or return $e->die_event;
                    }
                }
            }
        }

        $ret->{"transit"} = $transit;
    } elsif ($U->is_true($reservation->current_resource->type->catalog_item)) {
        $logger->info("resource is a catalog item...");
        my $copy = $e->search_asset_copy($search_acp_like_this)->[0];

        if ($copy) {
            return new OpenILS::Event(
                "OPEN_CIRCULATION_EXISTS",
                "payload" => {"captured" => 0, "copy" => $copy}
            ) if $copy->status == 1 and not $no_update_copy;

            $ret->{"mvr"} = get_mvr($copy->call_number->record);
            if ($no_update_copy) {
                $ret->{"new_copy_status"} = 15;
            } else {
                $copy->status(15);
                $e->update_asset_copy($copy) or return $e->die_event;
            }
        }
    }

    $e->commit or return $e->die_event;

    # create action trigger event to notify that reservation is available
    if ($reservation->email_notify) {
        my $ses = OpenSRF::AppSession->create('open-ils.trigger');
        $ses->request('open-ils.trigger.event.autocreate', 'reservation.available', $reservation, $reservation->pickup_lib);
    }

    # XXX I'm not sure whether these last two elements of the payload
    # actually get used anywhere.
    $ret->{"resource"} = $reservation->current_resource;
    $ret->{"type"} = $reservation->current_resource->type;
    return new OpenILS::Event("SUCCESS", "payload" => $ret);
}
__PACKAGE__->register_method(
    method   => "capture_reservation",
    api_name => "open-ils.booking.reservations.capture",
    argc     => 2,
    signature=> {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'mixed', desc =>
                'Reservation ID (number) or array of resource barcodes'}
        ],
        return => { desc => "An OpenILS Event object describing the outcome of the capture, with relevant payload." },
    }
);


sub cancel_reservation {
    my ($self, $client, $auth, $id_list) = @_;

    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    # Should the following permission really be checked as relates to each
    # individual reservation's request_lib?  Hrmm...
    return $e->die_event unless $e->allowed("ADMIN_BOOKING_RESERVATION");

    my $bresv_list = $e->search_booking_reservation([
        {"id" => $id_list},
        {"flesh" => 1, "flesh_fields" => {"bresv" => [
            "current_resource", "target_resource_type"
        ]}}
    ]);
    return $e->die_event if not $bresv_list;

    my @results = ();
    my $circ = OpenSRF::AppSession->connect("open-ils.circ") or
        return $e->die_event;
    foreach my $bresv (@$bresv_list) {
        $bresv->cancel_time("now");
        $e->update_booking_reservation($bresv) or do {
            $circ->disconnect;
            return $e->die_event;
        };
        $e->xact_commit;
        $e->xact_begin;

        if (
            $bresv->target_resource_type->catalog_item == "t" &&
            $bresv->current_resource
        ) {
            $logger->info("result of no-op checkin (upon cxl bresv) is " .
                $circ->request(
                    "open-ils.circ.checkin", $auth,
                    {"barcode" => $bresv->current_resource->barcode,
                        "noop" => 1}
                )->gather(1)->{"textcode"});
        }
        push @results, $bresv->id;
    }

    $e->disconnect;
    $circ->disconnect;

    return \@results;
}
__PACKAGE__->register_method(
    method   => "cancel_reservation",
    api_name => "open-ils.booking.reservations.cancel",
    argc     => 2,
    signature=> {
        params => [
            {type => "string", desc => "Authentication token"},
            {type => "array", desc => "List of reservation IDs"}
        ],
        return => { desc => "A list of canceled reservation IDs" },
    }
);


sub get_captured_reservations {
    my ($self, $client, $auth, $barcode, $which) = @_;

    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("VIEW_USER");
    return $e->die_event unless $e->allowed("ADMIN_BOOKING_RESERVATION");

    # fetch the patron for our uses in any case...
    my $patron = $U->fetch_user_by_barcode($barcode);
    return $patron if ref($patron) eq "HASH" and exists $patron->{"ilsevent"};

    my $bresv_flesh = {
        "flesh" => 1,
        "flesh_fields" => {"bresv" => [
            qw/target_resource_type current_resource/
        ]}
    };

    my $dispatch = {
        "patron" => sub {
            return $patron;
        },
        "ready" => sub {
            return $e->search_booking_reservation([
                {
                    "usr" => $patron->id,
                    "capture_time" => {"!=" => undef},
                    "pickup_time" => undef,
                    "start_time" => {"!=" => undef},
                    "cancel_time" => undef
                },
                $bresv_flesh
            ]) or $e->die_event;
        },
        "out" => sub {
            return $e->search_booking_reservation([
                {
                    "usr" => $patron->id,
                    "pickup_time" => {"!=" => undef},
                    "return_time" => undef,
                    "cancel_time" => undef
                },
                $bresv_flesh
            ]) or $e->die_event;
        },
        "in" => sub {
            return $e->search_booking_reservation([
                {
                    "usr" => $patron->id,
                    "return_time" => {">=" => "today"},
                    "cancel_time" => undef
                },
                $bresv_flesh
            ]) or $e->die_event;
        }
    };

    my $result = {};
    foreach (@$which) {
        my $f = $dispatch->{$_};
        if ($f) {
            my $r = &{$f}();
            return $r if (ref($r) eq "HASH" and exists $r->{"ilsevent"});
            $result->{$_} = $r;
        }
    }

    return $result;
}
__PACKAGE__->register_method(
    method   => "get_captured_reservations",
    api_name => "open-ils.booking.reservations.get_captured",
    argc     => 3,
    signature=> {
        params => [
            {type => "string", desc => "Authentication token"},
            {type => "string", desc => "Patron barcode"},
            {type => "array", desc => "Parts wanted (patron, ready, out, in?)"}
        ],
        return => { desc => "A hash of parts." } # XXX describe more fully
    }
);


sub get_bresv_by_returnable_resource_barcode {
    my ($self, $client, $auth, $barcode) = @_;

    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("VIEW_USER");
#    return $e->die_event unless $e->allowed("ADMIN_BOOKING_RESERVATION");

    my $rows = $e->json_query({
        "select" => {"bresv" => ["id"]},
        "from" => {
            "bresv" => {
                "brsrc" => {"field" => "id", "fkey" => "current_resource"}
            }
        },
        "where" => {
            "+brsrc" => {"barcode" => $barcode},
            "-and" => {
                "pickup_time" => {"!=" => undef},
                "cancel_time" => undef,
                "return_time" => undef
            }
        }
    }) or return $e->die_event;

    if (@$rows < 1) {
        $e->rollback;
        return $rows;
    } else {
        # More than one result might be possible, but we don't want to return
        # more than one at this time.
        my $id = $rows->[0]->{"id"};
        my $resp =$e->retrieve_booking_reservation([
            $id, {
                "flesh" => 2,
                "flesh_fields" => {
                    "bresv" => [qw/usr target_resource_type current_resource/],
                    "au" => ["card"]
                }
            }
        ]) or $e->die_event;
        $e->rollback;
        return $resp;
    }
}

__PACKAGE__->register_method(
    method   => "get_bresv_by_returnable_resource_barcode",
    api_name => "open-ils.booking.reservations.by_returnable_resource_barcode",
    argc     => 2,
    signature=> {
        params => [
            {type => "string", desc => "Authentication token"},
            {type => "string", desc => "Resource barcode"},
        ],
        return => { desc => "A fleshed bresv or an ilsevent on error" }
    }
);


1;
