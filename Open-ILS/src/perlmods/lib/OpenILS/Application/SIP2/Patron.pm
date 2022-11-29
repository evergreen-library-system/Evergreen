package OpenILS::Application::SIP2::Patron;
use strict; use warnings;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::System;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Const qw/:const/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Application::SIP2::Common;
my $U = 'OpenILS::Application::AppUtils';
my $SC = 'OpenILS::Application::SIP2::Common';

sub get_patron_details {
    my ($class, $session, %params) = @_;

    my $barcode = $params{barcode};
    my $password = $params{password};

    my $e = $session->editor;
    my $details = {valid_patron_password => 0};

    my $card = $e->search_actor_card([{
        barcode => $barcode
    }, {
        flesh => 3,
        flesh_fields => {
            ac => [qw/usr/],
            au => [qw/
                billing_address
                mailing_address
                profile
                home_ou
                net_access_level
                stat_cat_entries
            /],
            actscecm => [qw/stat_cat/]
        }
    }])->[0];

    return undef unless $card;

    my $patron = $details->{patron} = $card->usr;
    $card->usr($card->usr->id);
    $patron->card($card);
    $details->{patron_phone} = 
        $patron->day_phone || $patron->evening_phone || $patron->other_phone;

    if (my $addr = $patron->billing_address || $patron->mailing_address) {

        my $addrstr = join(' ', map {$_ || ''} (
            $addr->street1,
            $addr->street2,
            $addr->city . ',',
            $addr->county,
            $addr->state,
            $addr->country,
            $addr->post_code
        ));

        $addrstr =~ s/\s+/ /sg; # Compress spaces

        $details->{patron_address} = $addrstr;
    }

    if (defined $password) {
        # SIP still replies with the patron data if the password
        # is not valid.
        $details->{valid_patron_password} = 
            $U->verify_migrated_user_password($e, $patron->id, $password);
    }

    set_patron_privileges($session, $details);

    my $summary = $e->retrieve_money_open_user_summary($patron->id);
    $details->{balance_owed} = ($summary) ? $summary->balance_owed : 0;

    set_patron_summary_items($session, $details, %params);
    set_patron_summary_list_items($session, $details, %params);
    log_activity($session, $patron);

    return $details;
}

sub log_activity {
    my ($session, $patron) = @_;

    my $ewho = $session->sip_account->activity_who 
        || $session->config->{default_activity_who};
    $U->log_user_activity($patron->id, $ewho, 'verify');
}


# Sets:
#    holds_count
#    overdue_count
#    out_count
#    fine_count
#    recall_count
#    unavail_holds_count
sub set_patron_summary_items {
    my ($session, $details, %params) = @_;

    my $patron = $details->{patron};
    my $e = $session->editor;

    $details->{recall_count} = 0; # not supported

    $details->{hold_ids} = get_hold_ids($session, $patron);
    $details->{holds_count} = scalar(@{$details->{hold_ids}});

    $details->{unavailable_hold_ids} = get_hold_ids($session, $patron, 1);
    $details->{unavail_holds_count} = scalar(@{$details->{unavailable_hold_ids}});

    $details->{overdue_count} = 0;
    $details->{out_count} = 0;

    my $circ_summary = $e->retrieve_action_open_circ_list($patron->id);
    if ($circ_summary) { # undef if no circs for user
        my $overdue_ids = [ grep {$_ > 0} split(',', $circ_summary->overdue) ];
        my $out_ids = [ grep {$_ > 0} split(',', $circ_summary->out) ];
        $details->{overdue_count} = scalar(@$overdue_ids);
        $details->{out_count} = scalar(@$out_ids) + scalar(@$overdue_ids);
        $details->{items_overdue_ids} = $overdue_ids;
        $details->{items_out_ids} = $out_ids;
    } else {
        $details->{overdue_count} = 0;
        $details->{out_count} = 0;
        $details->{items_overdue_ids} = [];
        $details->{items_out_ids} = [];
    }

    my $xacts = $U->simplereq(
        'open-ils.actor',                                
        'open-ils.actor.user.transactions.history.have_balance',               
        $session->editor->authtoken,
        $patron->id
    );

    $details->{fine_count} = scalar(@$xacts);
}

sub get_hold_ids {
    my ($session, $patron, $unavail, $offset, $limit) = @_;

    my $e = $session->editor;

    my $holds_where = {
        usr => $patron->id,
        fulfillment_time => undef,
        cancel_time => undef
    };

    if ($unavail) {
        $holds_where->{'-or'} = [
            {current_shelf_lib => undef},
            {current_shelf_lib => {'!=' => {'+ahr' => 'pickup_lib'}}}
        ];

    } else {

        $holds_where->{current_shelf_lib} = {'=' => {'+ahr' => 'pickup_lib'}} 
            if $session->config->{msg64_hold_items_available};
    }

    my $query = {
        select => {ahr => ['id']},
        from => 'ahr',
        where => {'+ahr' => $holds_where}
    };

    $query->{offset} = $offset if $offset;
    $query->{limit} = $limit if $limit;

    my $id_hashes = $e->json_query($query);

    return [map {$_->{id}} @$id_hashes];
}

sub set_patron_summary_list_items {
    my ($session, $details, %params) = @_;
    my $e = $session->editor;

    my $list_items = $params{summary_list_items};

    return unless $list_items;

    # Start and end are 1-based.  Translate to zero-based for internal use.
    my $offset = $params{summary_start_item} ? $params{summary_start_item} - 1 : 0;
    my $end = $params{summary_end_item} ? $params{summary_end_item} - 1 : 10;
    my $limit = $end - $offset;

    add_hold_items($session, $details, $offset, $limit)
        if $list_items eq 'hold_items';

    add_hold_items($session, $details, $offset, $limit, 1)
        if $list_items eq 'unavailable_holds';

    add_items_out($session, $details, $offset, $limit)
        if $list_items eq 'charged_items';

    add_items_out($session, $details, $offset, $limit)
        if $list_items eq 'charged_items';

    add_fine_items($session, $details, $offset, $limit)
        if $list_items eq 'fine_items';

}

sub get_data_range {
    my ($array, $offset, $limit) = @_;

    return $array unless (defined $offset && defined $limit);

    return [
        grep { $_ } @$array[$offset .. ($offset + $limit - 1)]
    ];
}

sub add_hold_items {
    my ($session, $details, $offset, $limit, $unavailable) = @_;

    my $patron = $details->{patron};
    my $format = $session->config->{msg64_hold_datatype} || '';
    my $hold_ids = $unavailable ? 
        $details->{unavailable_hold_ids} : $details->{hold_ids};

    my @hold_items;
    for my $hold_id (@$hold_ids) {
        my $hold = $session->editor->retrieve_action_hold_request($hold_id);

        if ($format eq 'barcode') {
            my $copy = find_copy_for_hold($session, $hold);
            push(@hold_items, $copy->barcode) if $copy;
        } else {
            my $title = find_title_for_hold($session, $hold);
            push(@hold_items, $title) if $title;
        }
    }

    $details->{hold_items} = get_data_range(\@hold_items, $offset, $limit);
}

sub add_items_out {
    my ($session, $details, $offset, $limit) = @_;
    my $patron = $details->{patron};

    my @circ_ids = (@{$details->{items_out_ids}}, @{$details->{items_overdue_ids}});

    my $circ_ids = get_data_range(\@circ_ids, $offset, $limit);

    $details->{items_out} = [];
    for my $circ_id (@$circ_ids) {
        my $value = circ_id_to_value($session, $circ_id);
        push(@{$details->{items_out}}, $value);
    }
}

sub add_overdue_items {
    my ($session, $details, $offset, $limit) = @_;
    my $patron = $details->{patron};

    my @circ_ids = @{$details->{items_overdue_ids}};

    my $circ_ids = get_data_range(\@circ_ids, $offset, $limit);

    $details->{overdue_items} = [];
    for my $circ_id (@$circ_ids) {
        my $value = circ_id_to_value($session, $circ_id);
        push(@{$details->{items_out}}, $value);
    }
}

sub circ_id_to_value {
    my ($session, $circ_id) = @_;

    my $value = '';
    my $format = $session->config->{settings}->{msg64_summary_datatype} || '';

    if ($format eq 'barcode') {
        my $circ = $session->editor->retrieve_action_circulation([
            $circ_id, {
            flesh => 1,
            flesh_fields => {circ => ['target_copy']}
        }]);

        $value = $circ->target_copy->barcode;
        
    } else { # title

        my $circ = $session->editor->retrieve_action_circulation([
            $circ_id, {
            flesh => 4,
            flesh_fields => {
                circ => ['target_copy'],
                acp => ['call_number'],
                acn => ['record'],
                bre => ['simple_record']
            }
        }]);

        if ($circ->target_copy->call_number == -1) {
            $value = $circ->target_copy->dummy_title;
        } else {
            $value = 
                $circ->target_copy->call_number->record->simple_record->title;
        }
    }

    return $value;
}

# Hold -> reporter.hold_request_record -> display field for title.
sub find_title_for_hold {
    my ($session, $hold) = @_;
    my $e = $session->editor;

    my $bib_link = $e->retrieve_reporter_hold_request_record($hold->id);

    my $title_field = $e->search_metabib_flat_display_entry({
        source => $bib_link->bib_record, name => 'title'})->[0];

    return $title_field ? $title_field->value : '';
}

# Finds a representative copy for the given hold.  If no copy exists at
# all, undef is returned.  The only limit placed on what constitutes a
# "representative" copy is that it cannot be deleted.  Otherwise, any
# copy that allows us to find the hold later is good enough.
sub find_copy_for_hold {
    my ($session, $hold) = @_;
    my $e = $session->editor;

    return $e->retrieve_asset_copy($hold->current_copy)
        if $hold->current_copy; 

    return $e->retrieve_asset_copy($hold->target)
        if $hold->hold_type =~ /C|R|F/;

    return $e->search_asset_copy([
        {call_number => $hold->target, deleted => 'f'}, 
        {limit => 1}])->[0] if $hold->hold_type eq 'V';

    my $bre_ids = [$hold->target];

    if ($hold->hold_type eq 'M') {
        # find all of the bibs that link to the target metarecord
        my $maps = $e->search_metabib_metarecord_source_map(
            {metarecord => $hold->target});
        $bre_ids = [map {$_->record} @$maps];
    }

    my $vol_ids = $e->search_asset_call_number( 
        {record => $bre_ids, deleted => 'f'}, 
        {idlist => 1}
    );

    return $e->search_asset_copy([
        {call_number => $vol_ids, deleted => 'f'}, 
        {limit => 1}
    ])->[0];
}


sub set_patron_privileges {
    my ($session, $details) = @_;
    my $patron = $details->{patron};

    my $expire = DateTime::Format::ISO8601->new
        ->parse_datetime(clean_ISO8601($patron->expire_date));

    if ($expire < DateTime->now) {
        $logger->info("SIP2 Patron account is expired; all privileges blocked");
        $details->{charge_denied} = 1;
        $details->{recall_denied} = 1;
        $details->{renew_denied} = 1;
        $details->{holds_denied} = 1;
        return;
    }

    # Non-expired patrons are allowed all privileges when 
    # patron_status_permit_all is true.
    return if $session->config->{patron_status_permit_all};

    my $penalties = get_patron_penalties($session, $patron);

    $details->{too_many_overdue} = 1 if
        grep {$_->{id} == OILS_PENALTY_PATRON_EXCEEDS_OVERDUE_COUNT}
        @$penalties;

    $details->{too_many_fines} = 1 if
        grep {$_->{id} == OILS_PENALTY_PATRON_EXCEEDS_FINES}
        @$penalties;

    my $blocked = (
           $patron->barred eq 't'
        || $patron->active eq 'f'
        || $patron->card->active eq 'f'
    );

    my @block_tags = map {$_->{block_list}} grep {$_->{block_list}} @$penalties;

    return unless $blocked || @block_tags; # no blocks remain

    $details->{holds_denied} = ($blocked || grep {$_ =~ /HOLD/} @block_tags);

    # Ignore loan-related blocks?
    return if $session->config->{patron_status_permit_loans};

    $details->{charge_denied} = ($blocked || grep {$_ =~ /CIRC/} @block_tags);
    $details->{renew_denied} = ($blocked || grep {$_ =~ /RENEW/} @block_tags);

    # In evergreen, patrons cannot create Recall holds directly, but that
    # doesn't mean they would not have said privilege if the functionality
    # existed.  Base the ability to perform recalls on whether they have
    # checkout and holds privilege, since both would be needed for recalls.
    $details->{recall_denied} = 
        ($details->{charge_denied} || $details->{holds_denied});

}

# Returns an array of penalty hashes with keys "id" and "block_list"
sub get_patron_penalties {
    my ($session, $patron) = @_;

    return $session->editor->json_query({
        select => {csp => ['id', 'block_list']},
        from => {ausp => 'csp'},
        where => {
            '+ausp' => {
                usr => $patron->id,
                '-or' => [
                    {stop_date => undef},
                    {stop_date => {'>' => 'now'}}
                ],
                org_unit => 
                    $U->get_org_full_path($session->editor->requestor->ws_ou)
            }
        }
    });
}

sub add_fine_items {
    my ($session, $details, $offset, $limit) = @_;
    my $patron = $details->{patron};
    my $e = $session->editor;

    my @fines;
    my $AV_format = lc($session->config->{settings}->{av_format} || 'eg_legacy');

    # Do a prescan for validity and default to eg_legacy
    if ($AV_format ne "swyer_a" &&
        $AV_format ne "swyer_b" &&
        $AV_format ne "eg_legacy" &&
        $AV_format ne "3m") {

        syslog(LOG_WARNING => "SIP2 Unknown value for AV_format: $AV_format");
        $AV_format = "eg_legacy";
    }

    my $xacts = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.transactions.history.have_balance',
        $e->authtoken, $patron->id
    );

    foreach my $xact (@{$xacts}) {
        my ($title, $author, $line, $fee_type);

        if ($xact->last_billing_type eq 'Lost Materials') {
            $fee_type = 'LOST';
        } elsif ($xact->last_billing_type =~ /^Overdue/) {
            $fee_type = 'FINE';
        } else {
            $fee_type = 'FEE';
        }

        if ($xact->xact_type eq 'circulation') {
            my $circ = $e->retrieve_action_circulation([
                $xact->id, {
                    flesh => 2,
                    flesh_fields => {
                        circ => ['target_copy'],
                        acp => ['call_number']
                    }
                }
            ]);

            if ($circ->target_copy->call_number->id == -1) {
                $title = $circ->target_copy->dummy_title;
                $author = $circ->target_copy->dummy_author;

            } else {

                my $displays = $e->search_metabib_flat_display_entry({
                    source => $circ->target_copy->call_number->record,
                    name => ['title', 'author']
                });

                ($title) = map {$_->value} grep {$_->name eq 'title'} @$displays;
                ($author) = map {$_->value} grep {$_->name eq 'author'} @$displays;
            }

            # Scrub "/" chars since they are used in some cases 
            # to delineate title/author.
            if ($title) {
                $title =~ s/\///g;
            } else {
                $title = '';
            }

            if ($author) {
                $author =~ s/\///g;
            } else {
                $author = '';
            }
        }

        if ($AV_format eq "eg_legacy") {

            $line = $xact->balance_owed . " " . $xact->last_billing_type . " ";

            if ($xact->xact_type eq 'circulation') {
                $line .= "$title / $author";
            } else {
                $line .= $xact->last_billing_type;
            }

        } elsif ($AV_format eq "3m" or $AV_format eq "swyer_a") {

            $line = $xact->id . ' $' . $xact->balance_owed . " \"$fee_type\" ";

            if ($xact->xact_type eq 'circulation') {
                $line .= "$title";
            } else {
                $line .= $xact->last_billing_type;
            }

        } elsif ($AV_format eq "swyer_b") {

            $line =   "Charge-Number: " . $xact->id;
            $line .=  ", Amount-Due: "  . $xact->balance_owed;
            $line .=  ", Fine-Type: $fee_type";

            if ($xact->xact_type eq 'circulation') {
                $line .= ", Title: $title";
            } else {
                $line .= ", Title: " . $xact->last_billing_type;
            }
        }

        push @fines, $line;
    }

    $details->{fine_items} = get_data_range(\@fines, $offset, $limit);
}

sub block_patron {
    my ($class, $session, $patron_barcode, $block_msg) = @_;
    my $e = $session->{editor};

    my $details = OpenILS::Application::SIP2::Patron->get_patron_details(
        $session, barcode => $patron_barcode
    );

    return 0 unless $details;

    my $patron = $details->{patron};

    # Technically possible for a patron account to have no main card.
    return 0 if $patron->card && $patron->card->active eq 'f';

    # connect and start a new transaction
    $e->xact_begin; 

    $patron->card->active('f');

    if (!$e->update_actor_card($patron->card)) {
        my $evt = $e->die_event;
        $logger->error("SIP2: Block card update failed: " . $evt->{textcode});
        return 0;
    }

    my $penalty = Fieldmapper::actor::user_standing_penalty->new;
    $penalty->usr($patron->id);
    $penalty->org_unit($e->requestor->ws_ou || $e->requestor->home_ou);
    $penalty->set_date('now');
    $penalty->staff($e->requestor->id);
    $penalty->standing_penalty(20); # ALERT_NOTE

    my $note_msg = $e->retrieve_sip_screen_message('patron_block.penalty_note');
    my $note = $note_msg ? $note_msg->message : 'CARD BLOCKED BY SELF-CHECK MACHINE';

    $note .= "\n$block_msg" if $block_msg;

    my $title_msg = $e->retrieve_sip_screen_message('patron_block.title');
    my $title = $title_msg ? $title_msg->message : 'SIP Block';

    my $msg = {title => $title, message => $note};

    my $penalty_result = $U->simplereq(
      'open-ils.actor',
      'open-ils.actor.user.penalty.apply', $e->authtoken, $penalty, $msg);

    if ($U->event_code($penalty_result)) {
        my $textcode = $penalty_result->{textcode};
        $logger->error("SIP2: Block patron penalty failed: $textcode");
        $e->rollback; # rollback + disconnect
        return 0;
    }

    $e->commit;

    return 1;
}


1;
