package OpenILS::Application::Actor::ClosedDates;
use base 'OpenILS::Application';
use strict; use warnings;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::DateTime qw(:datetime);
use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

sub initialize { return 1; }

sub process_emergency {
    my( $self, $conn, $auth, $date ) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    return $e->die_event unless $e->allowed(
        'EMERGENCY_CLOSING', $date->org_unit);

    my $id = ref($date->emergency_closing) ? $date->emergency_closing->id : $date->emergency_closing;

    # Stage 1
    $e->xact_begin;
    my $rows = $e->json_query({
        from => ['action.emergency_closing_stage_1', $id]
    });
    $e->xact_commit;
    return unless ($rows && @$rows);

    $conn->respond({stage => 'start', stats => $$rows[0]});

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');

    # Stage 2 - circs
    my $circs = $e->search_action_emergency_closing_circulation(
        { emergency_closing => $id }
    );
    my $circ_total = scalar(@$circs);

    my $mod = 1;
    $mod = int($circ_total / 10) if ($circ_total >= 100);
    $mod = int($circ_total / 100) if ($circ_total >= 1000);

    my $count = 0;
    for my $circ (@$circs) {
        $e->xact_begin;
        my $rows = $e->json_query({ from => ['action.emergency_closing_stage_2_circ', $circ->id] });
        $e->xact_commit;
        $count++;
        $ses->request('open-ils.trigger.event.autocreate', 'checkout.due.emergency_closing', $circ, $e->requestor->ws_ou)
            if (ref($rows) && @$rows && $U->is_true($$rows[0]{'action.emergency_closing_stage_2_circ'}));
        $conn->respond({stage => 'circulations', circulations => [$count,$circ_total]})
            if ($mod == 1 or !($circ_total % $mod));
    }

    # Stage 3 - holds
    my $holds = $e->search_action_emergency_closing_hold(
        { emergency_closing => $id }
    );
    my $hold_total = scalar(@$holds);

    $mod = 1;
    $mod = int($hold_total / 10) if ($hold_total >= 100);
    $mod = int($hold_total / 100) if ($hold_total >= 1000);

    $count = 0;
    for my $hold (@$holds) {
        $e->xact_begin;
        my $rows = $e->json_query({ from => ['action.emergency_closing_stage_2_hold', $hold->id] });
        $e->xact_commit;
        $count++;
        $ses->request('open-ils.trigger.event.autocreate', 'hold.shelf_expire.emergency_closing', $hold, $e->requestor->ws_ou)
            if (ref($rows) && @$rows && $U->is_true($$rows[0]{'action.emergency_closing_stage_2_hold'}));
        $conn->respond({stage => 'holds', holds => [$count,$hold_total]})
            if ($mod == 1 or !($hold_total % $mod));
    }

    # Stage 2 - reservations
    my $ress = $e->search_action_emergency_closing_reservation(
        { emergency_closing => $id }
    );
    my $res_total = scalar(@$ress);

    $mod = 1;
    $mod = int($res_total / 10) if ($res_total >= 100);
    $mod = int($res_total / 100) if ($res_total >= 1000);

    $count = 0;
    for my $res (@$ress) {
        $e->xact_begin;
        my $rows = $e->json_query({ from => ['action.emergency_closing_stage_2_reservation', $res->id] });
        $e->xact_commit;
        $count++;
        $ses->request('open-ils.trigger.event.autocreate', 'booking.due.emergency_closing', $res, $e->requestor->ws_ou)
            if (ref($rows) && @$rows && $U->is_true($$rows[0]{'action.emergency_closing_stage_2_reservation'}));
        $conn->respond({stage => 'ress', ress => [$count,$res_total]})
            if ($mod == 1 or !($res_total % $mod));
    }

    # Stage 3
    my $eclosing = $e->retrieve_action_emergency_closing($id);
    $eclosing->process_end_time('now');
    $e->xact_begin;
    $e->update_action_emergency_closing($eclosing);
    $e->xact_commit;

    return {stage => 'complete', complete => 1};
}
__PACKAGE__->register_method( 
    method      => 'process_emergency',
    api_name    => 'open-ils.actor.org_unit.closed.process_emergency',
    stream      => 1,
    max_bundle_count => 1,
    signature   => q/Processes an emergency closing/
);

__PACKAGE__->register_method( 
    method => 'fetch_dates',
    api_name    => 'open-ils.actor.org_unit.closed.retrieve.all',
    signature   => q/
        Retrieves a list of closed date object IDs
    /
);

sub fetch_dates {
    my( $self, $conn, $auth, $args ) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $org = $$args{orgid} || $e->requestor->ws_ou;
    my @date = localtime;
    my $start = $$args{start_date} ||  #default to today 
        ($date[5] + 1900) .'-'. ($date[4] + 1) .'-'. $date[3];
    my $end = $$args{end_date} || '3000-01-01'; # Y3K, here I come..

    my $dates = $e->search_actor_org_unit_closed_date( 
        [{ 
            '-or' => [
                { close_start => { ">=" => $start }, close_end => { "<=" => $end } },
                { emergency_closing => { "!=" => undef }, "+aec" => { process_end_time => { "=" => undef } } }
            ],
            org_unit => $org,
        }, {flesh        => 2,
            flesh_fields => { aoucd => ['emergency_closing'], aec => ['status'] },
            join         => { "aec" => { type => "left" } },
            limit        => $$args{limit},
            offset       => $$args{offset}
        }], { idlist => $$args{idlist} } ) or return $e->event;

    if(!$$args{idlist} and @$dates) {
        $dates = [ sort { $a->close_start cmp $b->close_start } @$dates ];
    }

    return $dates;
}

__PACKAGE__->register_method( 
    method => 'fetch_date',
    api_name    => 'open-ils.actor.org_unit.closed.retrieve',
    signature   => q/
        Retrieves a single date object
    /
);

sub fetch_date {
    my( $self, $conn, $auth, $id ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $date = $e->retrieve_actor_org_unit_closed_date($id) or return $e->event;
    $date->emergency_closing(
        $e->retrieve_action_emergency_closing($date->emergency_closing)
    ) if $date->emergency_closing;
    return $date;
}


__PACKAGE__->register_method( 
    method => 'delete_date',
    api_name    => 'open-ils.actor.org_unit.closed.delete',
    signature   => q/
        Removes a single date object
    /
);

sub delete_date {
    my( $self, $conn, $auth, $id ) = @_;
    my $e = new_editor(authtoken=>$auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    my $date = $e->retrieve_actor_org_unit_closed_date($id) or return $e->die_event;
    if ($date->emergency_closing) {
        return $e->die_event unless $e->allowed(
            'EMERGENCY_CLOSING', $date->org_unit);
    }
    return $e->die_event unless $e->allowed(
        'actor.org_unit.closed_date.delete', $date->org_unit);
    $e->delete_actor_org_unit_closed_date($date) or return $e->die_event;
    $e->commit;
    return 1;
}




__PACKAGE__->register_method( 
    method => 'create_date',
    api_name    => 'open-ils.actor.org_unit.closed.create',
    signature   => q/
        Creates a new org closed data
    /
);

sub create_date {
    my( $self, $conn, $auth, $date, $emergency ) = @_;

    my $e = new_editor(authtoken=>$auth, xact =>1);
    return $e->die_event unless $e->checkauth;
    
    return $e->die_event unless $e->allowed(
        'actor.org_unit.closed_date.create', $date->org_unit);

    if ($emergency) {
        return $e->die_event
            unless $e->allowed('EMERGENCY_CLOSING', $date->org_unit);
        $e->create_action_emergency_closing($emergency)
            or return $e->die_event;
        $date->emergency_closing($emergency->id);
    }

    $e->create_actor_org_unit_closed_date($date) or return $e->die_event;

    my $newobj = $e->retrieve_actor_org_unit_closed_date($date->id)
        or return $e->die_event;

    $newobj->emergency_closing(
        $e->retrieve_action_emergency_closing($newobj->emergency_closing)
    ) if $emergency;

    $e->commit;
    return $newobj;
}


__PACKAGE__->register_method(
    method => 'edit_date',
    api_name    => 'open-ils.actor.org_unit.closed.update',
    signature   => q/
        Updates a closed date object
    /
);

sub edit_date {
    my( $self, $conn, $auth, $date ) = @_;
    my $e = new_editor(authtoken=>$auth, xact =>1);
    return $e->die_event unless $e->checkauth;
    
    # First make sure they have the right to update the selected date object
    my $odate = $e->retrieve_actor_org_unit_closed_date($date->id) 
        or return $e->die_event;

    if ($odate->emergency_closing) {
        return $e->die_event unless $e->allowed(
            'EMERGENCY_CLOSING', $odate->org_unit);
    }

    return $e->die_event unless $e->allowed(
        'actor.org_unit.closed_date.update', $odate->org_unit);

    $e->update_actor_org_unit_closed_date($date) or return $e->die_event;

    my $newobj = $e->retrieve_actor_org_unit_closed_date($date->id)
        or return $e->die_event;

    $newobj->emergency_closing(
        $e->retrieve_action_emergency_closing($newobj->emergency_closing)
    ) if $odate->emergency_closing;

    $e->commit;

    return $newobj;
}


__PACKAGE__->register_method(
    method  => 'is_probably_emergency_closing',
    api_name    => 'open-ils.actor.org_unit.closed_date.emergency_test',
    signature   => q/
        Returns a truthy value if the closing start date is either in
        the past or is nearer in the future than the longest configured
        circulation duration.
        @param auth An auth token
        @param date A closed date object
    /
);
sub is_probably_emergency_closing {
    my( $self, $conn, $auth, $date ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    # First, when is it?
    my $start_seconds = DateTime::Format::ISO8601->parse_datetime(
        clean_ISO8601($date->close_start)
    )->epoch;

    # Is it in the past?
    return 1 if ($start_seconds < time); # It is!

    # No? Let's see if it's coming up sooner than
    # the currently-furthest normal due date...
    my $rules = $e->search_config_rules_circ_duration({
        extended => {
            '>'     => {
                transform => 'interval_pl_timestamptz',
                params    => ['now'],
                value     => $date->close_start
            }
        }
    }); # That is basically: WHERE 'now'::timestamptz + extended > $date->close_start
        # which translates to "the closed start happens earlier than the theoretically
        # latest due date we could currently have, so it might need emergency
        # treatment.

    return scalar(@$rules); # No rows means "not emergency".
}


__PACKAGE__->register_method(
    method  => 'closed_dates_overlap',
    api_name    => 'open-ils.actor.org_unit.closed_date.overlap',
    signature   => q/
        Returns an object with 'start' and 'end' fields 
        start is the first day the org is open going backwards from 
        'date'.  end is the next day the org is open going
        forward from 'date'.
        @param auth An auth token
        @param orgid The org unit in question
        @param date The date to search
    /
);
sub closed_dates_overlap {
    my( $self, $conn, $auth, $orgid, $date ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->request(
        'open-ils.storage.actor.org_unit.closed_date.overlap', $orgid, $date );
}




1;
