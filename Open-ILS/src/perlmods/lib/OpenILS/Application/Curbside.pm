package OpenILS::Application::Curbside;

use strict;
use warnings;

use POSIX qw/strftime/;
use OpenSRF::AppSession;
use OpenILS::Application;
use base qw/OpenILS::Application/;

use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

use Digest::MD5 qw(md5_hex);

use DateTime;
use DateTime::Format::ISO8601;

my $date_parser = DateTime::Format::ISO8601->new;

use OpenSRF::Utils::Logger qw/$logger/;

sub fetch_mine { # returns appointments owned by $authtoken user, optional $org filter
    my ($self, $conn, $authtoken, $org, $limit, $offset) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    # NOTE: not checking if curbside is enabled here
    # because the pickup lib might be anything

    my $slots = $e->search_action_curbside([{
        patron    => $e->requestor->id,
        delivered => { '=' => undef },
        ( $org ? (org => $org) : () )
    },{
        ($limit  ? (limit  => $limit) : ()),
        ($offset ? (offset => $offset) : ()),
        flesh => 2, flesh_fields => {acsp => ['patron'], au => ['card']},
        order_by => { acsp => {slot => {direction => 'asc'}} }
    }]);

    $conn->respond($_) for @$slots;
    return undef;
}
__PACKAGE__->register_method(
    method   => "fetch_mine",
    api_name => "open-ils.curbside.fetch_mine",
    stream   => 1,
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Optional Library ID to filter further'},
            {type => 'number', desc => 'Fetch limit'},
            {type => 'number', desc => 'Fetch offset'},
        ],
        return => { desc => 'A stream of appointments that the authenticated user owns'}
    }
);

sub fetch_appointments { # returns appointment for user at location
    my ($self, $conn, $authtoken, $usr, $org) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    return new OpenILS::Event("BAD_PARAMS", "desc" => "No user ID supplied") unless $usr;

    unless ($usr == $e->requestor->id) {
        return $e->die_event unless $e->allowed("STAFF_LOGIN");
    }

    my $slots = $e->search_action_curbside([{
        patron    => $usr,
        delivered => { '=' => undef },
        org       => $org,
    },{
        order_by => { acsp => {slot => {direction => 'asc'}} }
    }]);

    $conn->respond($_) for @$slots;
    return undef;
}
__PACKAGE__->register_method(
    method   => "fetch_appointments",
    api_name => "open-ils.curbside.open_user_appointments_at_lib",
    stream   => 1,
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Patron ID'},
            {type => 'number', desc => 'Optional pickup library. If not supplied, taken from WS of session.'},
        ],
        return => { desc => 'A stream of appointments that the authenticated user owns'}
    }
);

sub fetch_holds_for_patron_at_pickup_lib {
    my ($self, $conn, $authtoken, $usr, $org) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    return new OpenILS::Event("BAD_PARAMS", "desc" => "No user ID supplied") unless $usr;

    my $holds = $e->search_action_hold_request({
        usr => $usr,
        current_shelf_lib => $org,
        pickup_lib => $org,
        shelf_time => {'!=' => undef},
        cancel_time => undef,
        fulfillment_time => undef
    }, { idlist => 1 });

    return scalar(@$holds);

}
__PACKAGE__->register_method(
    method   => "fetch_holds_for_patron_at_pickup_lib",
    api_name => "open-ils.curbside.patron.ready_holds_at_lib.count",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Patron ID'},
            {type => 'number', desc => 'Optional pickup library. If not supplied, taken from WS of session.'},
        ],
        return => { desc => 'Number of holds on the shelf for the patron at the specified library'}
    }
);

sub _flesh_and_emit_slots {
    my ($conn, $e, $slots) = @_;

    for my $s (@$slots) {
        my $start_time;
        my $end_time;
        if ($s->delivered) {
            $start_time = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($s->delivered));
            $end_time = $start_time->clone->add(seconds => 90); # 90 seconds is arbitrary
        }
        my $holds = $e->search_action_hold_request([{
            usr => $s->patron->id,
            current_shelf_lib => $s->org,
            pickup_lib => $s->org,
            shelf_time => {'!=' => undef},
            cancel_time => undef,
            ($s->delivered) ?
                (
                    '-and' => [ { fulfillment_time => {'>=' => $start_time->strftime('%FT%T%z') } },
                                { fulfillment_time => {'<=' => $end_time->strftime('%FT%T%z') } } ],
                ) :
                (fulfillment_time => undef),
        },{
            flesh => 1, flesh_fields => {ahr => ['current_copy']},
        }]);

        my $rhrr_list = $e->search_reporter_hold_request_record(
            {id => [ map { $_->id } @$holds ]}
        );

        my %bib_data = map {
            ($_->id => $e->retrieve_metabib_wide_display_entry( $_->bib_record))
        } @$rhrr_list;

        $conn->respond({slot_id => $s->id, slot => $s, holds => $holds, bib_data_by_hold => \%bib_data});
    }
}

sub fetch_delivered { # returns appointments delivered TODAY
    my ($self, $conn, $authtoken, $org, $limit, $offset) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    my $slots = $e->search_action_curbside([{
        org => $org,
        arrival => { '!=' => undef},
        delivered => { '>' => 'today'},
    },{
        ($limit  ? (limit  => $limit) : ()),
        ($offset ? (offset => $offset) : ()),
        flesh => 2, flesh_fields => {acsp => ['patron'], au => ['card']},
        order_by => { acsp => {delivered => {direction => 'desc'}} }
    }]);

    _flesh_and_emit_slots($conn, $e, $slots);

    return undef;
}
__PACKAGE__->register_method(
    method   => "fetch_delivered",
    api_name => "open-ils.curbside.fetch_delivered",
    stream   => 1,
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Library ID'},
            {type => 'number', desc => 'Fetch limit'},
            {type => 'number', desc => 'Fetch offset'},
        ],
        return => { desc => 'A stream of appointments that were delivered today'}
    }
);

sub fetch_latest_delivered { # returns appointments delivered TODAY
    my ($self, $conn, $authtoken, $org) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    my $slots = $e->search_action_curbside([{
        org => $org,
        arrival => { '!=' => undef},
        delivered => { '>' => 'today'},
    },{
        order_by => { acsp => {delivered => {direction => 'desc'}} }
    }],{ idlist => 1 });

    return md5_hex( join(',', @$slots) );
}
__PACKAGE__->register_method(
    method   => "fetch_latest_delivered",
    api_name => "open-ils.curbside.fetch_delivered.latest",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Library ID'},
        ],
        return => { desc => 'Hash of appointment IDs delivered today, or error event'}
    }
);

sub fetch_arrived {
    my ($self, $conn, $authtoken, $org, $limit, $offset) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    my $slots = $e->search_action_curbside([{
        org => $org,
        arrival => { '!=' => undef},
        delivered => undef,
    },{
        ($limit  ? (limit  => $limit) : ()),
        ($offset ? (offset => $offset) : ()),
        flesh => 3, flesh_fields => {acsp => ['patron'], au => ['card','standing_penalties'], ausp => ['standing_penalty']},
        order_by => { acsp => 'arrival' }
    }]);


    _flesh_and_emit_slots($conn, $e, $slots);

    return undef;
}
__PACKAGE__->register_method(
    method   => "fetch_arrived",
    api_name => "open-ils.curbside.fetch_arrived",
    stream   => 1,
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Library ID'},
            {type => 'number', desc => 'Fetch limit'},
            {type => 'number', desc => 'Fetch offset'},
        ],
        return => { desc => 'A stream of appointments for patrons that have arrived but are not delivered'}
    }
);

sub fetch_latest_arrived {
    my ($self, $conn, $authtoken, $org) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    my $slots = $e->search_action_curbside([{
        org => $org,
        arrival => { '!=' => undef},
        delivered => undef,
    },{
        order_by => { acsp => { arrival => { direction => 'desc' } } }
    }],{ idlist => 1 });

    return md5_hex( join(',', @$slots) );
}
__PACKAGE__->register_method(
    method   => "fetch_latest_arrived",
    api_name => "open-ils.curbside.fetch_arrived.latest",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Library ID'},
        ],
        return => { desc => 'Hash of appointment IDs for undelivered appointments'}
    }
);

sub fetch_staged {
    my ($self, $conn, $authtoken, $org, $limit, $offset) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    my $slots = $e->search_action_curbside([{
        org => $org,
        staged => { '!=' => undef},
        arrival => undef
    },{
        ($limit  ? (limit  => $limit) : ()),
        ($offset ? (offset => $offset) : ()),
        flesh => 3, flesh_fields => {acsp => ['patron'], au => ['card','standing_penalties'], ausp => ['standing_penalty']},
        order_by => { acsp => 'slot' }
    }]);

    _flesh_and_emit_slots($conn, $e, $slots);

    return undef;
}
__PACKAGE__->register_method(
    method   => "fetch_staged",
    api_name => "open-ils.curbside.fetch_staged",
    stream   => 1,
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Library ID'},
            {type => 'number', desc => 'Fetch limit'},
            {type => 'number', desc => 'Fetch offset'},
        ],
        return => { desc => 'A stream of appointments that are staged but patrons have not yet arrived'}
    }
);

sub fetch_latest_staged {
    my ($self, $conn, $authtoken, $org) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    my $slots = $e->search_action_curbside([{
        org => $org,
        staged => { '!=' => undef},
        arrival => undef
    },{
        order_by => [
            { class => acsp => field => slot => direction => 'desc' },
            { class => acsp => field => id   => direction => 'desc' }
        ]
    }],{ idlist => 1 });

    return md5_hex( join(',', @$slots) );
}
__PACKAGE__->register_method(
    method   => "fetch_latest_staged",
    api_name => "open-ils.curbside.fetch_staged.latest",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Library ID'},
        ],
        return => { desc => 'Hash of appointment IDs for staged appointment'}
    }
);

sub fetch_to_be_staged {
    my ($self, $conn, $authtoken, $org, $limit, $offset) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    my $gran = $U->ou_ancestor_setting_value($org, 'circ.curbside.granularity') || '15 minutes';
    my $gran_seconds = interval_to_seconds($gran);
    my $horizon = DateTime->now; # NOTE: does not need timezone set because it gets UTC, not floating, so we can math with it
    $horizon->add(seconds => $gran_seconds * 2);

    my $slots = $e->search_action_curbside([{
        org => $org,
        staged => undef,
        slot => { '<=' => $horizon->strftime('%FT%T%z') },
    },{
        ($limit  ? (limit  => $limit) : ()),
        ($offset ? (offset => $offset) : ()),
        flesh => 3, flesh_fields => {acsp => ['patron','stage_staff'], au => ['card','standing_penalties'], ausp => ['standing_penalty']},
        order_by => { acsp => 'slot' }
    }]);

    _flesh_and_emit_slots($conn, $e, $slots);

    return undef;
}
__PACKAGE__->register_method(
    method   => "fetch_to_be_staged",
    api_name => "open-ils.curbside.fetch_to_be_staged",
    stream   => 1,
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Library ID'},
            {type => 'number', desc => 'Fetch limit'},
            {type => 'number', desc => 'Fetch offset'},
        ],
        return => { desc => 'A stream of appointments that need to be staged'}
    }
);

sub fetch_latest_to_be_staged {
    my ($self, $conn, $authtoken, $org) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    my $gran = $U->ou_ancestor_setting_value($org, 'circ.curbside.granularity') || '15 minutes';
    my $gran_seconds = interval_to_seconds($gran);
    my $horizon = DateTime->now; # NOTE: does not need timezone set because it gets UTC, not floating, so we can math with it
    $horizon->add(seconds => $gran_seconds * 2);

    my $slots = $e->search_action_curbside([{
        org => $org,
        staged => undef,
        slot => { '<=' => $horizon->strftime('%FT%T%z') },
    },{
        order_by => [
            { class => acsp => field => slot => direction => 'desc' },
            { class => acsp => field => id   => direction => 'desc' }
        ]
    }]);

    return md5_hex( join(',', map { join('-', $_->id(), $_->stage_staff() // '', $_->arrival() // '') } @$slots) );
}
__PACKAGE__->register_method(
    method   => "fetch_latest_to_be_staged",
    api_name => "open-ils.curbside.fetch_to_be_staged.latest",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Library ID'},
        ],
        return => { desc => 'Hash of appointment IDs that needs to be staged'}
    }
);

sub times_for_date {
    my ($self, $conn, $authtoken, $date, $org) = @_;

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    my $start_obj = $date_parser->parse_datetime($date);
    return $conn->respond_complete unless ($start_obj);

    my $gran = $U->ou_ancestor_setting_value($org, 'circ.curbside.granularity') || '15 minutes';
    $gran .= ' minutes' if ($gran =~ /^\s*\d+\s*$/); # Assume minutes for bare numbers (maybe surrounded by spaces)

    my $gran_seconds = interval_to_seconds($gran);
    $gran_seconds = 600 if ($gran_seconds < 600); # No smaller than 10 minute intervals

    my $max = $U->ou_ancestor_setting_value($org, 'circ.curbside.max_concurrent') || 10;

    my $hoo = $e->retrieve_actor_org_unit_hours_of_operation($org);
    return undef unless ($hoo);

    my $dow = $start_obj->day_of_week_0;

    my $open_method = "dow_${dow}_open";
    my $close_method = "dow_${dow}_close";

    my $open_time = $hoo->$open_method;
    my $close_time = $hoo->$close_method;
    return $conn->respond_complete if ($open_time eq $close_time); # location closed that day

    my $tz = $U->ou_ancestor_setting_value($org, 'lib.timezone') || 'local';
    $start_obj = $date_parser->parse_datetime($date.'T'.$open_time)->set_time_zone($tz); # reset this to opening time
    my $end_obj = $date_parser->parse_datetime($date.'T'.$close_time)->set_time_zone($tz);

    my $now_obj = DateTime->now; # NOTE: does not need timezone set because it gets UTC, not floating, so we can math with it
    # Add two step intervals to avoid having an appointment be scheduled
    # sooner than the library could stage the items. Setting the earliest
    # available time to be no earlier than two intervals from now
    # is arbitrary and could be made configurable in the future, though
    # it does follow the hard-coding of the horizon in fetch_to_be_staged().
    $now_obj->add(seconds => 2 * $gran_seconds);

    my $closings = [];
    my $step_obj = $start_obj->clone;
    while (DateTime->compare($step_obj,$end_obj) < 0) { # inside HOO
        if (DateTime->compare($step_obj,$now_obj) >= 0) { # only offer times in the future
            my $step_ts = $step_obj->strftime('%FT%T%z');

            if (!@$closings) { # Look for closings that include this slot time.
                $closings = $e->search_actor_org_unit_closed_date(
                    {org_unit => $org, close_start => {'<=' => $step_ts }, close_end => {'>=' => $step_ts }}
                );
            }

            my $skip = 0;
            for my $closing (@$closings) {
                # If we have closings, we check that we're still inside at least one of them.
                # If we /are/ inside one then we just move on. Otherwise, we'll forget
                # them and check for closings with the next slot time.
                if (DateTime->compare($step_obj,$date_parser->parse_datetime(clean_ISO8601($closing->close_end))->set_time_zone($tz)) < 0) {
                    $step_obj->add(seconds => $gran_seconds);
                    $skip++;
                    last;
                }
            }
            next if $skip;
            $closings = [];

            my $other_slots = $e->search_action_curbside({org => $org, slot => $step_ts}, {idlist => 1});
            my $available = $max - scalar(@$other_slots);
            $available = $available < 0 ? 0 : $available; # so truthiness testing is always easy in the client

            $conn->respond([$step_obj->strftime('%T'), $available]);
        }
        $step_obj->add(seconds => $gran_seconds);
    }

    $e->disconnect;
    return undef;
}
__PACKAGE__->register_method(
    method   => "times_for_date",
    api_name => "open-ils.curbside.times_for_date",
    stream   => 1,
    argc     => 2,
    signature=> {
        params => [
            {type => "string", desc => "Authentication token"},
            {type => "string", desc => "Date to find times for"},
            {type => "number", desc => "Library ID (default ws_ou)"},
        ],
        return => {desc => 'A stream of array refs, structure: ["hh:mm:ss",$available_count]; event on error.'}
    },
    notes   => 'Restricted to logged in users to avoid spamming induced load'
);

sub create_update_appointment {
    my ($self, $conn, $authtoken, $patron, $date, $time, $org, $notes) = @_;
    my $mode = 'create';
    $mode = 'update' if ($self->api_name =~ /update/);

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    $org ||= $e->requestor->ws_ou;

    return new OpenILS::Event("CURBSIDE_NOT_ALLOWED") unless ($U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    ));

    unless ($patron == $e->requestor->id) {
        return $e->die_event unless $e->allowed("STAFF_LOGIN");
    }

    my $date_obj = $date_parser->parse_datetime($date); # no TZ necessary, just using it to test the input and get DOW
    return undef unless ($date_obj);

    if ($time =~ /^\d\d:\d\d$/) {
        $time .= ":00"; # tack on seconds if needed to keep
                        # interval_to_seconds happy
    }

    my $slot;

    # do they already have an open slot?
    # NOTE: once arrival is set, it's past the point of editing.
    my $old_slot = $e->search_action_curbside({
        patron  => $patron,
        org     => $org,
        slot    => { '!=' => undef },
        arrival => undef
    })->[0];
    if ($old_slot) {
        if ($mode eq 'create') {
            my $ev = new OpenILS::Event("CURBSIDE_EXISTS");
            $e->disconnect;
            return $ev;
        } else {
            $slot = $old_slot;
        }
    }

    my $gran = $U->ou_ancestor_setting_value($org, 'circ.curbside.granularity') || '15 minutes';
    my $max = $U->ou_ancestor_setting_value($org, 'circ.curbside.max_concurrent') || 10;

    # some sanity checking
    my $hoo = $e->retrieve_actor_org_unit_hours_of_operation($org);
    return undef unless ($hoo);

    my $dow = $date_obj->day_of_week_0;

    my $open_method = "dow_${dow}_open";
    my $close_method = "dow_${dow}_close";

    my $open_time = $hoo->$open_method;
    my $close_time = $hoo->$close_method;
    return undef if ($open_time eq $close_time); # location closed that day

    my $open_seconds = interval_to_seconds($open_time);
    my $close_seconds = interval_to_seconds($close_time);

    my $time_seconds = interval_to_seconds($time);
    my $gran_seconds = interval_to_seconds($gran);

    return undef if ($time_seconds < $open_seconds); # too early
    return undef if ($time_seconds > $close_seconds + 1); # too late (/at/ closing allowed)

    my $time_into_open_second = $time_seconds - $open_seconds;
    if (my $extra_time = $time_into_open_second % $gran) { # a remainder means we got a time we shouldn't have
        $time_into_open_second -= $extra_time; # just back it off to have staff gather earlier
    }

    my $tz = $U->ou_ancestor_setting_value($org, 'lib.timezone') || 'local';
    $date_obj = $date_parser->parse_datetime($date.'T'.$open_time)->set_time_zone($tz);

    my $slot_ts = $date_obj->add(seconds => $time_into_open_second)->strftime('%FT%T%z');

    # finally, confirm that there aren't too many already
    my $other_slots = $e->search_action_curbside(
        { org => $org,
          slot => $slot_ts,
          ( $slot ? (id => { '<>' => $slot->id }) : () ) # exclude our own slot from the count
        },
        {idlist => 1}
    );
    if (scalar(@$other_slots) >= $max) { # oops... return error
        my $ev = new OpenILS::Event("CURBSIDE_MAX_FOR_TIME");
        $e->disconnect;
        return $ev;
    }

    my $method = 'update_action_curbside';
    if ($mode eq 'create' or !$slot) {
        $slot = $e->search_action_curbside({
            patron  => $patron,
            org     => $org,
            slot    => undef,
            arrival => undef,
        })->[0];
    }

    if (!$slot) { # just in case the hold-ready reactor isn't in place
        $slot = Fieldmapper::action::curbside->new;
        $slot->isnew(1);
        $slot->patron($patron);
        $slot->org($org);
        $slot->notes($notes) if ($notes);
        $method = 'create_action_curbside';
    } else {
        $slot->notes($notes) if ($notes);
        $slot->ischanged(1);
        $method = 'update_action_curbside';
    }

    $slot->slot($slot_ts);
    $e->$method($slot) or return $e->die_event;

    $e->commit;
    $conn->respond_complete($e->retrieve_action_curbside($slot->id));

    OpenSRF::AppSession
        ->create('open-ils.trigger')
        ->request(
            'open-ils.trigger.event.autocreate',
            'hold.confirm_curbside',
            $slot, $slot->org);

    return undef;
}
__PACKAGE__->register_method(
    method   => "create_update_appointment",
    api_name => "open-ils.curbside.update_appointment",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Patron ID'},
            {type => 'string', desc => 'New Date'},
            {type => 'string', desc => 'New Time'},
            {type => 'number', desc => 'Library ID (default ws_ou)'},
        ],
        return => { desc => 'An action::curbside record on success, '.
                            'an ILS Event on config, permission, or '.
                            'recoverable errors, or nothing on bad '.
                            'or silly data'}
    }
);

__PACKAGE__->register_method(
    method   => "create_update_appointment",
    api_name => "open-ils.curbside.create_appointment",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Patron ID'},
            {type => 'string', desc => 'Date'},
            {type => 'string', desc => 'Time'},
            {type => 'number', desc => 'Library ID (default ws_ou)'},
        ],
        return => { desc => 'An action::curbside record on success, '.
                            'an ILS Event on config, permission, or '.
                            'recoverable errors, or nothing on bad '.
                            'or silly data'}
    }
);

sub delete_appointment {
    my ($self, $conn, $authtoken, $appointment) = @_;
    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    my $slot = $e->retrieve_action_curbside($appointment);
    return undef unless ($slot);

    unless ($slot->patron == $e->requestor->id) {
        return $e->die_event unless $e->allowed("STAFF_LOGIN");
    }

    $e->delete_action_curbside($slot) or return $e->die_event;
    $e->commit;

    return -1;
}
__PACKAGE__->register_method(
    method   => "delete_appointment",
    api_name => "open-ils.curbside.delete_appointment",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Appointment ID'},
        ],
        return => { desc => '-1 on success, nothing when no appointment found, '.
                            'or an ILS Event on permission error'}
    }
);

sub manage_staging_claim {
    my ($self, $conn, $authtoken, $appointment) = @_;
    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("STAFF_LOGIN");

    my $slot = $e->retrieve_action_curbside($appointment);
    return undef unless ($slot);

    if ($self->api_name =~ /unclaim/) {
        $slot->clear_stage_staff();
    } else {
        $slot->stage_staff($e->requestor->id);
    }

    $e->update_action_curbside($slot) or return $e->die_event;
    $e->commit;

    return $e->retrieve_action_curbside([
        $slot->id, {
            flesh => 3,
            flesh_fields => {acsp => ['patron','stage_staff'], au => ['card','standing_penalties'], ausp => ['standing_penalty']},
        }
    ]);
}
__PACKAGE__->register_method(
    method   => "manage_staging_claim",
    api_name => "open-ils.curbside.claim_staging",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Appointment ID'},
        ],
        return => { desc => 'Appointment on success, nothing when no appointment found, '.
                            'an ILS Event on permission error'}
    }
);
__PACKAGE__->register_method(
    method   => "manage_staging_claim",
    api_name => "open-ils.curbside.unclaim_staging",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Appointment ID'},
        ],
        return => { desc => 'Appointment on success, nothing when no appointment found, '.
                            'an ILS Event on permission error'}
    }
);

sub mark_staged {
    my ($self, $conn, $authtoken, $appointment) = @_;
    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("STAFF_LOGIN");

    my $slot = $e->retrieve_action_curbside($appointment);
    return undef unless ($slot);

    $slot->staged('now');
    $slot->stage_staff($e->requestor->id);
    $e->update_action_curbside($slot) or return $e->die_event;
    $e->commit;

    return $e->retrieve_action_curbside($slot->id);
}
__PACKAGE__->register_method(
    method   => "mark_staged",
    api_name => "open-ils.curbside.mark_staged",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Appointment ID'},
        ],
        return => { desc => 'Appointment on success, nothing when no appointment found, '.
                            'an ILS Event on permission error'}
    }
);

sub mark_unstaged {
    my ($self, $conn, $authtoken, $appointment) = @_;
    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("STAFF_LOGIN");

    my $slot = $e->retrieve_action_curbside($appointment);
    return undef unless ($slot);

    $slot->clear_staged();
    $slot->clear_stage_staff();
    $e->update_action_curbside($slot) or return $e->die_event;
    $e->commit;

    return $e->retrieve_action_curbside($slot->id);
}
__PACKAGE__->register_method(
    method   => "mark_unstaged",
    api_name => "open-ils.curbside.mark_unstaged",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Appointment ID'},
        ],
        return => { desc => 'Appointment on success, nothing when no appointment found, '.
                            'an ILS Event on permission error'}
    }
);

sub mark_arrived {
    my ($self, $conn, $authtoken, $appointment) = @_;
    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    my $slot = $e->retrieve_action_curbside($appointment);
    return undef unless ($slot);

    unless ($slot->patron == $e->requestor->id) {
        return $e->die_event unless $e->allowed("STAFF_LOGIN");
    }

    $slot->arrival('now');

    $e->update_action_curbside($slot) or return $e->die_event;
    $e->commit;

    return $e->retrieve_action_curbside($slot->id);
}
__PACKAGE__->register_method(
    method   => "mark_arrived",
    api_name => "open-ils.curbside.mark_arrived",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Appointment ID'},
        ],
        return => { desc => 'Appointment on success, nothing when no appointment found, '.
                            'or an ILS Event on permission error'}
    }
);

sub mark_delivered {
    my ($self, $conn, $authtoken, $appointment) = @_;
    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("STAFF_LOGIN");

    my $slot = $e->retrieve_action_curbside($appointment);
    return undef unless ($slot);

    if (!$slot->staged) {
        $slot->staged('now');
        $slot->stage_staff($e->requestor->id);
    }

    if (!$slot->arrival) {
        $slot->arrival('now');
    }

    $slot->delivered('now');
    $slot->delivery_staff($e->requestor->id);

    $e->update_action_curbside($slot) or return $e->die_event;
    $e->commit;

    my $holds = $e->search_action_hold_request({
        usr => $slot->patron,
        current_shelf_lib => $slot->org,
        pickup_lib => $slot->org,
        shelf_time => {'!=' => undef},
        cancel_time => undef,
        fulfillment_time => undef
    });

    my $circ_sess = OpenSRF::AppSession->connect('open-ils.circ');
    my @requests = map {
        $circ_sess->request( # Just try as hard as possible to check out everything
            'open-ils.circ.checkout.full.override',
            $authtoken, { patron => $slot->patron, copyid => $_->current_copy }
        )
    } @$holds;

    my @successful_checkouts;
    my $successful_patron;
    for my $r (@requests) {
        my $co_res = $r->gather(1);
        $conn->respond($co_res);
        next if (ref($co_res) eq 'ARRAY'); # success is always singular

        if ($co_res->{textcode} eq 'SUCCESS') { # that's great news...
            push @successful_checkouts, $co_res->{payload}->{circ}->id;
            $successful_patron = $co_res->{payload}->{circ}->usr;
        }
    }

    $conn->respond_complete($e->retrieve_action_curbside($slot->id));

    $circ_sess->request(
        'open-ils.circ.checkout.batch_notify.session.atomic',
        $authtoken,
        $successful_patron,
        \@successful_checkouts
    ) if (@successful_checkouts);

    $circ_sess->disconnect;
    return undef;
}
__PACKAGE__->register_method(
    method   => "mark_delivered",
    api_name => "open-ils.curbside.mark_delivered",
    stream   => 1,
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'number', desc => 'Appointment ID'},
        ],
        return => { desc => 'Nothing for no appointment found, '.
                            'a stream of open-ils.circ.checkout.full.override '.
                            'responses followed by the finalized slot, '.
                            'or an ILS Event on permission error'}
    }
);

1;
