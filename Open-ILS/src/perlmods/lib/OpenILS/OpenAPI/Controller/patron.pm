package OpenILS::OpenAPI::Controller::patron;
use OpenILS::OpenAPI::Controller;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Application::AppUtils;

our $VERSION = 1;
our $U = "OpenILS::Application::AppUtils";

sub deliver_user {
    my ($controller, $ses, $usr) = @_;
    return OpenILS::OpenAPI::Controller::retrieve_one_object_via_pcrud(
        $controller => $ses,
        actor_user => $usr => {au => [qw/card cards addresses profile groups/]}
    );
}

# New subroutine for fleshing the user-id-by-barcode-or-username method output
sub user_by_identifier_string {
    my ($c, $ses, $barcode, $username) = @_;

    my $uid = $U->simplereq(
        'open-ils.actor', 'open-ils.actor.user.retrieve_id_by_barcode_or_username',
        $ses, $barcode, $username
    );

    do { $c->res->code(404); return $uid; } if ref($uid); # ILS Event objects are refs
    return deliver_user($c, $ses, $uid);
}

sub find_users {
    my ($c, $ses, $fields, $ops, $values, $limit, $offset) = @_;
    $limit ||= 100;
    $offset ||= 0;

    do { $c->res->code(400); return {error=>"No search terms provided"}; }
        unless ($fields and @$fields);

    return new_editor(personality=>'open-ils.pcrud', authtoken=>$ses)->search_actor_user([
        { -and => [
            { deleted => 'f', active => 't' },
            OpenILS::OpenAPI::Controller::where_clause_from_triples($fields, $ops, $values)
        ]},
        {limit => $limit, offset => $offset, flesh => 1,
         flesh_fields => {au => [qw/card cards addresses profile groups/]},
         order_by => {au => [qw/usrname/]}
        }
    ]);
}

sub confirm_circ_for_patron {
    my ($circ_id, $must_match_user) = @_;

    my $e = new_editor();
    my $circ = $e->retrieve_action_circulation([
        $circ_id, {flesh => 1, flesh_fields => { circ => ['target_copy'] }}
    ]);

    die 'invalid circulation id' unless $circ;

    if ($must_match_user) { # if passed, make sure the session user owns the circ
        die 'invalid circulation id' unless $circ->usr == $must_match_user;
    }

    return $circ;
}

sub circ_result_with_error_wrapper {
    my $c = shift;
    my $res = shift;
    $res = [$res] if (ref($res) ne 'ARRAY');

    my $errors = [ grep { $$_{textcode} ne 'SUCCESS' } @$res ];
    $c->res->code(403) if @$errors;
    return { errors => int(scalar(@$errors)), result => $res };
}

sub checkout_item {
    my ($c, $ses, $userid, $copy_barcode) = @_;
    return circ_result_with_error_wrapper($c,
        $U->simplereq(
            'open-ils.circ', 'open-ils.circ.checkout.full', $ses,
            { barcode => $copy_barcode, patron_id => $userid }
        )
    );
}

sub checkin_circ {
    my ($c, $ses, $circid, $must_match_user) = @_;
    return circ_result_with_error_wrapper($c,
        $U->simplereq(
            'open-ils.circ', 'open-ils.circ.checkin', $ses,
            { barcode => confirm_circ_for_patron($circid, $must_match_user)->target_copy->barcode, force => 1, noop => 1 }
        )
    );
}

sub renew_circ {
    my ($c, $ses, $circid, $must_match_user) = @_;
    my $circ = confirm_circ_for_patron($circid, $must_match_user);
    return circ_result_with_error_wrapper($c,
        $U->simplereq(
            'open-ils.circ', 'open-ils.circ.renew', $ses,
            { copy_id => $circ->target_copy->id, patron_id => $circ->usr}
        )
    );
}

sub update_user_parts {
    my ($c, $ses, $update_parts) = @_;

    my $orig_pw = delete $$update_parts{current_password};

    my %results;
    for my $part ( keys %$update_parts ) {
        my $res = $U->simplereq(
            'open-ils.actor', "open-ils.actor.user.$part.update",
            $ses => $$update_parts{$part} => $orig_pw
        ) or die "user update call failed";
        if (ref($res)) {
            $results{$part} = { success => 0, error => $res };
        } else {
            $results{$part} = { success => 1 };
        }
    }

    return \%results;
};

sub circulation_history {
    my ($c, $ses, $userid, $limit, $offset, $sort, $before, $after) = @_;
    return transactions_by_state($c, $ses, $userid, 'all', $limit, $offset, $sort, $before, $after, 'circulation')
}

sub usr_at_events {
    my ($c, $ses, $user_id, $limit, $offset, $before, $after, $hooks, $event_id) = @_;
    my $e = new_editor(authtoken => $ses);

    my $options = {
        limit  => $limit,
        offset => $offset,
        order_by   => [{class=>'atev', field=>'run_time', direction=>'desc'}]
    };

    my $filter = {context_user => $user_id};
    if ($before and $after) {
        $$filter{run_time} = {'between' => [$after, $before]};
    } elsif ($before) {
        $$filter{run_time} = {'<' => $before};
    } elsif ($after) {
        $$filter{run_time} = {'>' => $after};
    }

    $$filter{event_def} = [
        map {$_->id} @{$e->search_action_trigger_event_definition({hook=>$hooks})}
    ] if ($hooks);

    if ($event_id) {
        $$filter{id} = $event_id;
        $$options{flesh} = 2;
        $$options{flesh_fields} = {
            atevdef => [qw/hook owner validator reactor cleanup_success cleanup_failure opt_in_setting env params/],
            atev => [qw/event_def template_output error_output async_output context_library context_bib context_item/],
        };
    }

    my $events = new_editor(authtoken => $ses)->search_action_trigger_event([
        $filter, $options
    ]);

    return [ map {$_->id} @$events] unless $event_id;
    return $$events[0];
}

sub transactions_by_state {
    my ($c, $ses, $user_id, $state, $limit, $offset, $sort, $before, $after, $type) = @_;
    $sort = 'desc' if ($sort and !grep {uc($sort) eq $_} qw/ASC DESC/);

    my $method = '';
    if ($state eq 'all') {
        $method = 'open-ils.actor.user.transactions.history';
    } elsif (grep { $_ eq $state } qw/have_charge still_open have_balance have_bill have_bill_or_payment have_payment/) {
        $method .= "open-ils.actor.user.transactions.history.$state";
    }

    die 'Invalid transaction type request' unless $method;

    my $options = {
        limit  => $limit,
        offset => $offset,
        sort   => uc($sort)
    };

    my $filters = {};
    if ($before and $after) {
        $$filter{xact_start} = {'between' => [$after, $before]};
    } elsif ($before) {
        $$filter{xact_start} = {'<' => $before};
    } elsif ($after) {
        $$filter{xact_start} = {'>' => $after};
    }

    return $U->simplereq(
        'open-ils.actor', $method, $ses, $user_id, $type, $filters, $options
    );
}

sub update_usr_message {
    my ($c, $ses, $ses_user, $userid, $message_id, $blob) = @_;
    my $e = new_editor(personality => 'open-ils.pcrud', authtoken => $ses, xact=>1);
    my $msg = $e->retrieve_actor_usr_message($message_id);

    if (!$msg or $msg->usr != $userid) {
        $e->rollback;
        $c->res->code(404);
        return undef;
    }

    my %parts = (
        title => undef,
        message => undef,
        stop_date => undef,
        pub => undef,
        deleted => undef
    );

    OpenILS::OpenAPI::Controller::apply_blob_to_object($msg, $blob, \%parts);

    $msg->editor($ses_user);
    $msg->edit_date('now');

    if (!$e->update_actor_usr_message($msg)) {
        $e->rollback;
        $c->res->code(403);
        return undef;
    }

    $msg = $e->retrieve_actor_usr_message($message_id);
    $e->commit;

    return $msg;
}

sub archive_usr_message {
    my ($c, $ses, $ses_user, $userid, $message_id) = @_;
    return update_usr_message(
        $c, $ses, $ses_user, $userid, $message_id, {deleted => 't'}
    ) ? 1 : undef;
}

sub usr_messages {
    my ($c, $ses, $userid, $pub_only, $message_id) = @_;

    my $filter = {
        usr => $userid,
        deleted => 'f',
        '-or' => [ {stop_date => undef}, {stop_date => {'>' => 'now'}} ]
    };
    $$filter{id} = $message_id if ($message_id);

    my $messages = new_editor(
        personality => 'open-ils.pcrud',
        authtoken => $ses
    )->search_actor_usr_message(
        $filter
    );

    $messages = [grep {$U->is_true($_->pub)} @$messages]
        if ($pub_only);

    return [ map {$_->id} @$messages] unless $message_id;
    return $$messages[0];
}

sub standing_penalties {
    my ($c, $ses, $userid, $pub_only, $penalty_id) = @_;

    my $filter = {
        usr => $userid,
        '-or' => [ {stop_date => undef}, {stop_date => {'>' => 'now'}} ]
    };
    $$filter{id} = $penalty_id if ($penalty_id);

    my $penalties = new_editor(personality => 'open-ils.pcrud', authtoken => $ses)->search_actor_user_standing_penalty([
        $filter,
        { flesh => 1, flesh_fields => {ausp => ['standing_penalty','usr_message']} }
    ]);

    $penalties = [grep {$U->is_true($_->standing_penalty->pub) and $U->is_true($_->usr_message->pub)} @$penalties]
        if ($pub_only);

    return [ map {$_->id} @$penalties] unless $penalty_id;
    return $penalties;
}

sub usr_activity {
    my ($c, $ses, $user_id, $maxage, $limit, $offset, $sort) = @_;
    $sort = 'desc' if (!$sort or ($sort and !grep {uc($sort) eq $_} qw/ASC DESC/));
    $limit ||= 100;
    $offset ||= 0;

    my $filters = {usr => $user_id};
    $$filters{event_time} = {'>' => $maxage} if ($maxage);

    return new_editor(personality=>'open-ils.pcrud', authtoken=>$ses)->search_actor_usr_activity([
        $filters,
        {   flesh => 1,
            flesh_fields => {auact => ['etype']},
            limit => $limit,
            offset => $offset,
            order_by => [{class => auact => field => event_time => direction => $sort}]
        }
    ]);

}

1;
