package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenSRF::EX qw/:try/;
use OpenILS::Event;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Cache;
use OpenILS::Utils::DateTime qw/:datetime/;
use Digest::MD5 qw(md5_hex);
use Business::Stripe;
use Data::Dumper;
$Data::Dumper::Indent = 0;
use DateTime;
use DateTime::Format::ISO8601;
my $U = 'OpenILS::Application::AppUtils';
use List::MoreUtils qw/uniq/;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST GET);
use CGI;

sub prepare_extended_user_info {
    my $self = shift;
    my @extra_flesh = @_;
    my $e = $self->editor;

    # are we already in a transaction?
    my $local_xact = !$e->{xact_id};
    $e->xact_begin if $local_xact;

    # keep the original user object so we can restore
    # login-specific data (e.g. workstation)
    my $usr = $self->ctx->{user};

    $self->ctx->{user} = $self->editor->retrieve_actor_user([
        $self->ctx->{user}->id,
        {
            flesh => 2,
            flesh_fields => {
                au => [qw/card home_ou addresses ident_type locale billing_address mailing_address waiver_entries stat_cat_entries/, @extra_flesh],
                "aou" => ["billing_address"],
                "actscecm" => ["stat_cat"]
            }
        }
    ]);

    $e->rollback if $local_xact;

    $self->ctx->{user}->wsid($usr->wsid);
    $self->ctx->{user}->ws_ou($usr->ws_ou);

    # discard replaced (negative-id) addresses.
    $self->ctx->{user}->addresses([
        grep {$_->id > 0} @{$self->ctx->{user}->addresses} ]);

    return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR
        unless $self->ctx->{user};

    return;
}

# Given an event returned by a failed attempt to create a hold, do we have
# permission to override?  XXX Should the permission check be scoped to a
# given org_unit context?
sub test_could_override {
    my ($self, $event) = @_;

    return 0 unless $event;
    return 1 if $self->editor->allowed($event->{textcode} . ".override");
    return 1 if $event->{"fail_part"} and
        $self->editor->allowed($event->{"fail_part"} . ".override");
    return 0;
}

# Find out whether we care that local copies are available
sub local_avail_concern {
    my ($self, $hold_target, $hold_type, $pickup_lib) = @_;

    my $would_block = $self->ctx->{get_org_setting}->
        ($pickup_lib, "circ.holds.hold_has_copy_at.block");
    my $would_alert = (
        $self->ctx->{get_org_setting}->
            ($pickup_lib, "circ.holds.hold_has_copy_at.alert") and
                not $self->cgi->param("override")
    ) unless $would_block;

    if ($would_block or $would_alert) {
        my $args = {
            "hold_target" => $hold_target,
            "hold_type" => $hold_type,
            "org_unit" => $pickup_lib
        };
        my $local_avail = $U->simplereq(
            "open-ils.circ",
            "open-ils.circ.hold.has_copy_at", $self->editor->authtoken, $args
        );
        $logger->info(
            "copy availability information for " . Dumper($args) .
            " is " . Dumper($local_avail)
        );
        if (%$local_avail) { # if hash not empty
            $self->ctx->{hold_copy_available} = $local_avail;
            return ($would_block, $would_alert);
        }
    }

    return (0, 0);
}

# context additions:
#   user : au object, fleshed
sub load_myopac_prefs {
    my $self = shift;
    my $cgi = $self->cgi;
    my $e = $self->editor;
    my $pending_addr = $cgi->param('pending_addr');
    my $replace_addr = $cgi->param('replace_addr');
    my $delete_pending = $cgi->param('delete_pending');

    $self->prepare_extended_user_info;
    my $user = $self->ctx->{user};

    # Check whether or not to provide account renewal link
    if ($user->billing_address and $user->billing_address->valid and $user->billing_address->valid eq 't') {
        $self->ctx->{valid_billing_address} = 1;
    } else {
        $self->ctx->{valid_billing_address} = 0;
    }
    if ($user->mailing_address and $user->mailing_address->valid and $user->mailing_address->valid eq 't') {
        $self->ctx->{valid_mailing_address} = 1;
    } else {
        $self->ctx->{valid_mailing_address} = 0;
    }

    $self->check_account_exp();

    my $lock_usernames = $self->ctx->{get_org_setting}->($e->requestor->home_ou, 'opac.lock_usernames');
    if(defined($lock_usernames) and $lock_usernames == 1) {
        # Policy says no username changes
        $self->ctx->{username_change_disallowed} = 1;
    } else {
        my $username_unlimit = $self->ctx->{get_org_setting}->($e->requestor->home_ou, 'opac.unlimit_usernames');
        if(!$username_unlimit) {
            my $regex_check = $self->ctx->{get_org_setting}->($e->requestor->home_ou, 'opac.barcode_regex');
            if(!$regex_check) {
                # Default is "starts with a number"
                $regex_check = '^\d+';
            }
            # You already have a username?
            if($regex_check and $self->ctx->{user}->usrname !~ /$regex_check/) {
                $self->ctx->{username_change_disallowed} = 1;
            }
        }
    }

    return Apache2::Const::OK unless
        $pending_addr or $replace_addr or $delete_pending;

    my @form_fields = qw/address_type street1 street2 city county state country post_code/;

    my $paddr;
    if( $pending_addr ) { # update an existing pending address

        ($paddr) = grep { $_->id == $pending_addr } @{$user->addresses};
        return Apache2::Const::HTTP_BAD_REQUEST unless $paddr;
        $paddr->$_( $cgi->param($_) ) for @form_fields;

    } elsif( $replace_addr ) { # create a new pending address for 'replace_addr'

        $paddr = Fieldmapper::actor::user_address->new;
        $paddr->isnew(1);
        $paddr->usr($user->id);
        $paddr->pending('t');
        $paddr->replaces($replace_addr);
        $paddr->$_( $cgi->param($_) ) for @form_fields;

    } elsif( $delete_pending ) {
        $paddr = $e->retrieve_actor_user_address($delete_pending);
        return Apache2::Const::HTTP_BAD_REQUEST unless
            $paddr and $paddr->usr == $user->id and $U->is_true($paddr->pending);
        $paddr->isdeleted(1);
    }

    my $resp = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.address.pending.cud',
        $e->authtoken, $paddr);

    if( $U->event_code($resp) ) {
        $logger->error("Error updating pending address: $resp");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    # in light of these changes, re-fetch latest data
    $e->xact_begin;
    $self->prepare_extended_user_info;
    $e->rollback;

    return Apache2::Const::OK;
}

sub load_myopac_prefs_notify {
    my $self = shift;
    my $e = $self->editor;

    my $stat = $self->_load_user_with_prefs;
    return $stat if $stat;

    my $user_prefs = $self->fetch_optin_prefs;
    $user_prefs = $self->update_optin_prefs($user_prefs)
        if $self->cgi->request_method eq 'POST';

    $self->ctx->{opt_in_settings} = $user_prefs;

    return Apache2::Const::OK
        unless $self->cgi->request_method eq 'POST';

    my %settings;
    my $set_map = $self->ctx->{user_setting_map};

    foreach my $key (qw/
        opac.default_phone
        opac.default_sms_notify
    /) {
        my $val = $self->cgi->param($key);
        $settings{$key}= $val unless $$set_map{$key} eq $val;
    }

    my $key = 'opac.default_sms_carrier';
    my $val = $self->cgi->param('sms_carrier');
    $settings{$key}= $val unless $$set_map{$key} eq $val;

    $key = 'opac.hold_notify';
    my @notify_methods = ();
    if ($self->cgi->param($key . ".email") eq 'on') {
        push @notify_methods, "email";
    }
    if ($self->cgi->param($key . ".phone") eq 'on') {
        push @notify_methods, "phone";
    }
    if ($self->cgi->param($key . ".sms") eq 'on') {
        push @notify_methods, "sms";
    }
    $val = join("|",@notify_methods);
    $settings{$key}= $val unless $$set_map{$key} eq $val;

    # Send the modified settings off to be saved
    $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.patron.settings.update',
        $self->editor->authtoken, undef, \%settings);

    # re-fetch user prefs
    $self->ctx->{updated_user_settings} = \%settings;

    # update holds: check if any changes affect any holds
    my @llchgs = $self->_parse_prefs_notify_hold_related();
    my @ffectedChgs;

    if ( $self->cgi->param('hasHoldsChanges') ) {
        # propagate pref_notify changes to holds
        for my $chset (@llchgs){
            # FIXME is this still needed?
        }
    
    }
    else {
        my $holds = $U->simplereq('open-ils.circ', 'open-ils.circ.holds.retrieve.by_usr.with_notify',
            $e->authtoken, $e->requestor->id);

        if (@$holds > 0) {

            my $default_phone_changes = {};
            my $sms_changes           = {};
            my $new_phone;
            my $new_carrier;
            my $new_sms;
            for my $chset (@llchgs) {
                next if scalar(@$chset) < 3;
                my ($old, $new, $field) = @$chset;

                my $bool = $field =~ /_notify/ ? 1 : 0;

                # find holds that would change
                my $affected = [];
                foreach my $hold (@$holds) {
                    if ($field eq 'email_notify') {
                        my $curr = $hold->{$field} eq 't' ? 'true' : 'false';
                        push @$affected, $hold if $curr ne $new;
                    } elsif ($field eq 'default_phone') {
                        my $old_phone = $hold->{phone_notify} // '';
                        $new_phone = $new // '';
                        push @{ $default_phone_changes->{ $old_phone } }, $hold->{id}
                            if $old_phone ne $new_phone;
                    } elsif ($field eq 'phone_notify') {
                        my $curr = ($hold->{$field} // '' ne '') ? 'true' : 'false';
                        push @$affected, $hold if $curr ne $new;
                    } elsif ($field eq 'sms_notify') {
                        my $curr = ($hold->{$field} // '' ne '') ? 'true' : 'false';
                        push @$affected, $hold if $curr ne $new;
                    } elsif ($field eq 'sms_info') {
                        my $old_carrier = $hold->{'sms_carrier'} // '';
                        my $old_sms = $hold->{'sms_notify'} // '';
                        $new_carrier = $new->{carrier} // '';
                        $new_sms = $new->{sms} // '';
                        if (!($old_carrier eq $new_carrier && $old_sms eq $new_sms)) {
                            push @{ $sms_changes->{ join("\t", $old_carrier, $old_sms) } }, $hold->{id};
                        }
                    }
                }

                # append affected array to chset
                if (scalar(@$affected) > 0){
                    push(@$chset, [ map { $_->{id} } @$affected ]);
                    push(@ffectedChgs, $chset);
                }
            }


            foreach my $old_phone (keys %$default_phone_changes) {
                push(@ffectedChgs, [ $old_phone, $new_phone, 'default_phone', $default_phone_changes->{$old_phone} ]);
            }
            foreach my $old_sms_info (keys %$sms_changes) {
                my ($old_carrier, $old_sms) = split /\t/, $old_sms_info;
                push(@ffectedChgs, [
                                        { carrier => $old_carrier, sms => $old_sms },
                                        { carrier => $new_carrier, sms => $new_sms },
                                        'sms_info',
                                        $sms_changes->{$old_sms_info}
                                   ]);
            }

            if ( scalar(@ffectedChgs) ){
                $self->ctx->{affectedChgs} = \@ffectedChgs;
            }
        }
    }

    return $self->_load_user_with_prefs || Apache2::Const::OK;
}

sub _parse_prefs_notify_hold_related {

    my $self = shift;
    my $for_update = shift;

    # create an array of change arrays
    my @chgs;

    my @phone_notify = $self->cgi->multi_param('phone_notify[]');
    push(@chgs, \@phone_notify) if scalar(@phone_notify);

    my $turning_on_phone_notify  = !$for_update &&
                                   scalar(@phone_notify) &&
                                   $phone_notify[1] eq 'true';
    my $turning_off_phone_notify = !$for_update &&
                                   scalar(@phone_notify) &&
                                   $phone_notify[1] eq 'false';

    my $changing_default_phone = 0;
    if (!$turning_off_phone_notify) {
        my @default_phone = $self->cgi->multi_param('default_phone[]');
        if ($for_update) {
            while (scalar(@default_phone) > 0) {
                my $chg = [ splice(@default_phone, 0, 4) ];
                if (scalar(@default_phone) > 0 && $default_phone[0] eq 'on') {
                    push @$chg, shift(@default_phone);
                    push(@chgs, $chg);
                    $changing_default_phone = 1;
                }
            }
        } else {
            if (scalar(@default_phone)) {
                push @chgs, \@default_phone;
                $changing_default_phone = 1;
            }
        }
    }

    if ($turning_on_phone_notify && $changing_default_phone) {
        # we don't need to have both the phone_notify and default_phone
        # changes; the latter will suffice
        @chgs = grep { $_->[2] ne 'phone_notify' } @chgs;
    } elsif ($turning_on_phone_notify && !$changing_default_phone) {
        # replace the phone_notify change with a default_phone change
        @chgs = grep { $_->[2] ne 'phone_notify' } @chgs;
        my $default_phone = $self->cgi->param('opac.default_phone'); # we assume this is set
        push @chgs, [ '', $default_phone, 'default_phone' ];
    }

    # on to SMS
    # ... since both carrier and number are needed to send an SMS notifcation,
    # we need to treat the pair as a unit
    my @sms_notify = $self->cgi->multi_param('sms_notify[]');
    push(@chgs, \@sms_notify) if scalar(@sms_notify);

    my $turning_on_sms_notify  = !$for_update &&
                                   scalar(@sms_notify) &&
                                   $sms_notify[1] eq 'true';
    my $turning_off_sms_notify = !$for_update &&
                                   scalar(@sms_notify) &&
                                   $sms_notify[1] eq 'false';

    my $changing_sms_info = 0;
    if (!$turning_off_sms_notify) {
        my @sms_carrier = $self->cgi->multi_param('default_sms_carrier_id[]');
        my @sms = $self->cgi->multi_param('default_sms[]');

        if (scalar(@sms) || scalar(@sms_carrier)) {
            my $new_carrier = scalar(@sms_carrier) ? $sms_carrier[1] : $self->cgi->param('sms_carrier');
            my $new_sms = scalar(@sms) ? $sms[1] : $self->cgi->param('opac.default_sms_notify');
            push @chgs, [
                            { carrier => '', sms => '' },
                            { carrier => $new_carrier, sms => $new_sms },
                            'sms_info'
                        ];
           $changing_sms_info = 1;
        }
    }

    my @sms_info = $self->cgi->multi_param('sms_info[]'); # only sent by confirmation page
    if (scalar(@sms_info)) {
        while (scalar(@sms_info) > 0) {
            my $chg = [ splice(@sms_info, 0, 4) ];
            if (scalar(@sms_info) > 0 && $sms_info[0] eq 'on') {
                push @$chg, shift(@sms_info);
                my ($carrier, $sms) = split /,/, $chg->[0], -1;
                $chg->[0] = { carrier => $carrier, sms => $sms };
                ($carrier, $sms) = split /,/, $chg->[1], -1;
                $chg->[1] = { carrier => $carrier, sms => $sms };
                push(@chgs, $chg);
                $changing_sms_info = 1;
            }
        }
    }

    if ($turning_on_sms_notify && $changing_sms_info) {
        # we don't need to have both the sms_notify and sms_info
        # changes; the latter will suffice
        @chgs = grep { $_->[2] ne 'sms_notify' } @chgs;
    } elsif ($turning_on_sms_notify && !$changing_sms_info) {
        # replace the sms_notify change with a sms_info change
        @chgs = grep { $_->[2] ne 'sms_notify' } @chgs;
        my $sms_info = {
            carrier => $self->cgi->param('sms_carrier'),
            sms     => $self->cgi->param('opac.default_sms_notify'),
        };
        push @chgs, [ { carrier => '', sms => ''}, $sms_info, 'sms_info' ];
    }

    my @email_notify = $self->cgi->multi_param('email_notify[]');
    push(@chgs, \@email_notify) if scalar(@email_notify);

    if ($for_update) {
        # if we're updating, keep only the ones that have been
        # explicitly checked by the user
        @chgs = grep { scalar(@$_) == 5 && $_->[4] eq 'on' } @chgs;
    }
    return @chgs;
}

sub load_myopac_prefs_notify_changed_holds {
    my $self = shift;
    my $e = $self->editor;

    my $hasChanges = $self->cgi->param('hasHoldsChanges');
    
    return $self->_load_user_with_prefs || Apache2::Const::OK unless $hasChanges;

    my @ll = $self->_parse_prefs_notify_hold_related(1);

    my @updates;
    for my $chset (@ll){
        my ($old, $new, $type, $holdids, $doit) = @$chset;
        next if $doit ne 'on';
        
        # parse string list into array list
        my @holdids = split(',', $holdids);
        
        if ($type =~ /_notify/){
            # translate true/false string into 1/0
            $old = $old eq 'true' ? 1 : 0;
            $new = $new eq 'true' ? 1 : 0;
        }

        my $update;
        if ($type eq 'sms_info') {
            if ($new->{carrier} eq '' && $new->{sms} eq '') {
                # clear SMS number first to avoid check contrainst issue
                $update = $U->simplereq('open-ils.circ', "open-ils.circ.holds.batch_update_holds_by_notify",
                    $e->authtoken, $e->requestor->id, [@holdids], $old->{sms}, $new->{sms}, 'default_sms');
                push (@updates, $update) if (scalar(@$update) > 0);
                $update = $U->simplereq('open-ils.circ', "open-ils.circ.holds.batch_update_holds_by_notify",
                    $e->authtoken, $e->requestor->id, [@holdids], $old->{carrier}, $new->{carrier}, 'default_sms_carrier_id');
                push (@updates, $update) if (scalar(@$update) > 0);
            } else {
                $update = $U->simplereq('open-ils.circ', "open-ils.circ.holds.batch_update_holds_by_notify",
                    $e->authtoken, $e->requestor->id, [@holdids], $old->{carrier}, $new->{carrier}, 'default_sms_carrier_id');
                push (@updates, $update) if (scalar(@$update) > 0);
                $update = $U->simplereq('open-ils.circ', "open-ils.circ.holds.batch_update_holds_by_notify",
                    $e->authtoken, $e->requestor->id, [@holdids], $old->{sms}, $new->{sms}, 'default_sms');
                push (@updates, $update) if (scalar(@$update) > 0);
            }
        } else {
            $update = $U->simplereq('open-ils.circ', "open-ils.circ.holds.batch_update_holds_by_notify",
                $e->authtoken, $e->requestor->id, [@holdids], $old, $new, $type);

            # append affected array to chset
            if (scalar(@$update) > 0){
                push(@updates, $update);
            }
        }
    }

    $self->ctx->{'updated'} = \@updates;

    return $self->_load_user_with_prefs || Apache2::Const::OK;

}

sub fetch_optin_prefs {
    my $self = shift;
    my $e = $self->editor;

    # fetch all of the opt-in settings the user has access to
    # XXX: user's should in theory have options to opt-in to notices
    # for remote locations, but that opens the door for a large
    # set of generally un-used opt-ins.. needs discussion
    my $opt_ins =  $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.event_def.opt_in.settings.atomic',
        $e->authtoken, $e->requestor->home_ou);

    # some opt-ins are staff-only
    $opt_ins = [ grep { $U->is_true($_->opac_visible) } @$opt_ins ];

    # fetch user setting values for each of the opt-in settings
    my $user_set = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.patron.settings.retrieve',
        $e->authtoken,
        $e->requestor->id,
        [map {$_->name} @$opt_ins]
    );

    return [map { {cust => $_, value => $user_set->{$_->name} } } @$opt_ins];
}

sub load_myopac_messages {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $cgi = $self->cgi;

    my $limit  = $cgi->param('limit') || 20;
    my $offset = $cgi->param('offset') || 0;

    my $pcrud = OpenSRF::AppSession->create('open-ils.pcrud');
    $pcrud->connect();

    my $action = $cgi->param('action') || '';
    if ($action) {
        my ($changed, $failed) = $self->_handle_message_action($pcrud, $action);
        if ($changed > 0 || $failed > 0) {
            $ctx->{message_update_action} = $action;
            $ctx->{message_update_changed} = $changed;
            $ctx->{message_update_failed} = $failed;
            $self->update_dashboard_stats();
        }
    }

    my $single = $cgi->param('single') || 0;
    my $id = $cgi->param('message_id');

    my $messages;
    my $fetch_all = 1;
    if (!$action && $single && $id) {
        $messages = $self->_fetch_and_mark_read_single_message($pcrud, $id);
        if (scalar(@$messages) == 1) {
            $ctx->{display_single_message} = 1;
            $ctx->{patron_message_id} = $id;
            $fetch_all = 0;
        }
    }

    if ($fetch_all) {
        # fetch all the messages
        ($ctx->{patron_messages_count}, $messages) =
            $self->_fetch_user_messages($pcrud, $offset, $limit);
    }

    $pcrud->kill_me;

    foreach my $aum (@$messages) {

        push @{ $ctx->{patron_messages} }, {
            id          => $aum->id,
            title       => $aum->title,
            message     => $aum->message,
            create_date => $aum->create_date,
            edit_date   => $aum->edit_date,
            is_read     => defined($aum->read_date) ? 1 : 0,
            library     => $aum->sending_lib->name,
        };
    }

    $ctx->{patron_messages_limit} = $limit;
    $ctx->{patron_messages_offset} = $offset;

    return Apache2::Const::OK;
}

sub _fetch_and_mark_read_single_message {
    my $self = shift;
    my $pcrud = shift;
    my $id = shift;

    $pcrud->request('open-ils.pcrud.transaction.begin', $self->editor->authtoken)->gather(1);
    my $messages = $pcrud->request(
        'open-ils.pcrud.search.auml.atomic',
        $self->editor->authtoken,
        {
            usr     => $self->editor->requestor->id,
            deleted => 'f',
            id      => $id,
        },
        {
            flesh => 1,
            flesh_fields => { auml => ['sending_lib'] },
        }
    )->gather(1);
    if (@$messages) {
        $messages->[0]->read_date('now');
        $pcrud->request(
            'open-ils.pcrud.update.auml',
            $self->editor->authtoken,
            $messages->[0]
        )->gather(1);
    }
    $pcrud->request('open-ils.pcrud.transaction.commit', $self->editor->authtoken)->gather(1);

    $self->update_dashboard_stats();

    return $messages;
}

sub _fetch_user_messages {
    my $self = shift;
    my $pcrud = shift;
    my $offset = shift;
    my $limit = shift;

    my %paging = ($limit or $offset) ? (limit => $limit, offset => $offset) : ();

    my $all_messages = $pcrud->request(
        'open-ils.pcrud.id_list.auml.atomic',
        $self->editor->authtoken,
        {
            usr     => $self->editor->requestor->id,
            deleted => 'f'
        },
        {}
    )->gather(1);

    my $messages = $pcrud->request(
        'open-ils.pcrud.search.auml.atomic',
        $self->editor->authtoken,
        {
            usr     => $self->editor->requestor->id,
            deleted => 'f'
        },
        {
            flesh => 1,
            flesh_fields => { auml => ['sending_lib'] },
            order_by => { auml => 'create_date DESC' },
            %paging
        }
    )->gather(1);

    return scalar(@$all_messages), $messages;
}

sub _handle_message_action {
    my $self = shift;
    my $pcrud = shift;
    my $action = shift;
    my $cgi = $self->cgi;

    my @ids = $cgi->param('message_id');
    return (0, 0) unless @ids;

    my $changed = 0;
    my $failed = 0;
    $pcrud->request('open-ils.pcrud.transaction.begin', $self->editor->authtoken)->gather(1);
    for my $id (@ids) {
        my $aum = $pcrud->request(
            'open-ils.pcrud.retrieve.auml',
            $self->editor->authtoken,
            $id
        )->gather(1);
        next unless $aum;
        if      ($action eq 'mark_read') {
            $aum->read_date('now');
        } elsif ($action eq 'mark_unread') {
            $aum->clear_read_date();
        } elsif ($action eq 'mark_deleted') {
            $aum->deleted('t');
        }
        $pcrud->request('open-ils.pcrud.update.auml', $self->editor->authtoken, $aum)->gather(1) ?
            $changed++ :
            $failed++;
    }
    if ($failed) {
        $pcrud->request('open-ils.pcrud.transaction.rollback', $self->editor->authtoken)->gather(1);
        $changed = 0;
        $failed = scalar(@ids);
    } else {
        $pcrud->request('open-ils.pcrud.transaction.commit', $self->editor->authtoken)->gather(1);
    }
    return ($changed, $failed);
}

sub _load_lists_and_settings {
    my $self = shift;
    my $e = $self->editor;
    my $stat = $self->_load_user_with_prefs;
    unless ($stat) {
        my $exclude = 0;
        my $setting_map = $self->ctx->{user_setting_map};
        $exclude = $$setting_map{'opac.default_list'} if ($$setting_map{'opac.default_list'});
        $self->ctx->{bookbags} = $e->search_container_biblio_record_entry_bucket(
            [
                {owner => $self->ctx->{user}->id, btype => 'bookbag', id => {'<>' => $exclude}}, {
                    order_by => {cbreb => 'name'},
                    limit => $self->cgi->param('limit') || 10,
                    offset => $self->cgi->param('offset') || 0
                }
            ]
        );

        # We need a separate bookbag object that contains the full list for use in the basket selection dropdowns
        $self->ctx->{bookbags_complete} = $e->search_container_biblio_record_entry_bucket(
            [
                {owner => $self->ctx->{user}->id, btype => 'bookbag'}, {
                    order_by => {cbreb => 'name'}
                }
            ]
        );

        # We also want a total count of the user's bookbags.
        my $q = {
            'select' => { 'cbreb' => [ { 'column' => 'id', 'transform' => 'count', 'aggregate' => 'true', 'alias' => 'count' } ] },
            'from' => 'cbreb',
            'where' => { 'btype' => 'bookbag', 'owner' => $self->ctx->{user}->id }
        };
        my $r = $e->json_query($q);
        $self->ctx->{bookbag_count} = $r->[0]->{'count'};
        # Someone has requested that we use the default list's name
        # rather than "Default List."
        if ($exclude) {
            $q = {
                'select' => {'cbreb' => ['name']},
                'from' => 'cbreb',
                'where' => {'id' => $exclude}
            };
            $r = $e->json_query($q);
            $self->ctx->{default_bookbag} = $r->[0]->{'name'};
        }
    } else {
        return $stat;
    }
    return undef;
}

sub update_optin_prefs {
    my $self = shift;
    my $user_prefs = shift;
    my $e = $self->editor;
    my @settings = $self->cgi->param('setting');
    my %newsets;

    # apply now-true settings
    for my $applied (@settings) {
        # see if setting is already applied to this user
        next if grep { $_->{cust}->name eq $applied and $_->{value} } @$user_prefs;
        $newsets{$applied} = OpenSRF::Utils::JSON->true;
    }

    # remove now-false settings
    for my $pref (grep { $_->{value} } @$user_prefs) {
        $newsets{$pref->{cust}->name} = undef
            unless grep { $_ eq $pref->{cust}->name } @settings;
    }

    $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.patron.settings.update',
        $e->authtoken, $e->requestor->id, \%newsets);

    # update the local prefs to match reality
    for my $pref (@$user_prefs) {
        $pref->{value} = $newsets{$pref->{cust}->name}
            if exists $newsets{$pref->{cust}->name};
    }

    return $user_prefs;
}

sub _load_user_with_prefs {
    my $self = shift;
    my $stat = $self->prepare_extended_user_info('settings');
    return $stat if $stat; # not-OK

    $self->ctx->{user_setting_map} = {
        map { $_->name => OpenSRF::Utils::JSON->JSON2perl($_->value) }
            @{$self->ctx->{user}->settings}
    };

    return undef;
}

sub _get_bookbag_sort_params {
    my ($self, $param_name) = @_;

    # The interface that feeds this cgi parameter will provide a single
    # argument for a QP sort filter, and potentially a modifier after a period.
    # In practice this means the "sort" parameter will be something like
    # "titlesort" or "authorsort.descending".
    my $sorter = $self->cgi->param($param_name) || "";
    my $modifier;
    if ($sorter) {
        $sorter =~ s/^(.*?)\.(.*)/$1/;
        $modifier = $2 || undef;
    }

    return ($sorter, $modifier);
}

sub _prepare_bookbag_container_query {
    my ($self, $container_id, $sorter, $modifier) = @_;

    return sprintf(
        "container(bre,bookbag,%d,%s)%s%s",
        $container_id, $self->editor->authtoken,
        ($sorter ? " sort($sorter)" : ""),
        ($modifier ? "#$modifier" : "")
    );
}

sub _prepare_anonlist_sorting_query {
    my ($self, $list, $sorter, $modifier) = @_;

    return sprintf(
        "record_list(%s)%s%s",
        join(",", @$list),
        ($sorter ? " sort($sorter)" : ""),
        ($modifier ? "#$modifier" : "")
    );
}


sub load_myopac_prefs_settings {
    my $self = shift;

    my @user_prefs = qw/
        opac.hits_per_page
        opac.default_search_location
        opac.default_pickup_location
        opac.temporary_list_no_warn
        ui.show_search_highlight
    /;

    my $stat = $self->_load_user_with_prefs;
    return $stat if $stat;

    # if behind-desk holds are supported and the user
    # setting which controls the value is opac-visible,
    # add the setting to the list of settings to manage.
    # note: this logic may need to be changed later to
    # check whether behind-the-desk holds are supported
    # anywhere the patron may select as a pickup lib.
    my $e = $self->editor;
    my $bdous = $self->ctx->{get_org_setting}->(
        $e->requestor->home_ou,
        'circ.holds.behind_desk_pickup_supported');

    if ($bdous) {
        my $setting =
            $e->retrieve_config_usr_setting_type(
                'circ.holds_behind_desk');

        if ($U->is_true($setting->opac_visible)) {
            push(@user_prefs, 'circ.holds_behind_desk');
            $self->ctx->{behind_desk_supported} = 1;
        }
    }

    my $use_privacy_waiver = $self->ctx->{get_org_setting}->(
        $e->requestor->home_ou, 'circ.privacy_waiver');

    return Apache2::Const::OK
        unless $self->cgi->request_method eq 'POST';

    # some setting values from the form don't match the
    # required value/format for the db, so they have to be
    # individually translated.

    my %settings;
    my $set_map = $self->ctx->{user_setting_map};

    foreach my $key (@user_prefs) {
        my $val = $self->cgi->param($key);
        $settings{$key}= $val unless $$set_map{$key} eq $val;
    }

    # Set search highlight to a boolean so it's simple to check after retrieval
    # Also set it to false if we didn't receive it because html form didn't send it,
    # but the user would've seen the setting and saved with it false

    if ($settings{'ui.show_search_highlight'} eq 'on'){
        $settings{'ui.show_search_highlight'} = JSON::true; }
    else {
        $settings{'ui.show_search_highlight'} = JSON::false;}

    # Used by the settings update form when warning on history delete.
    my $clear_circ_history = 0;
    my $clear_hold_history = 0;

    # true if we need to show the warning on next page load.
    my $hist_warning_needed = 0;
    my $hist_clear_confirmed = $self->cgi->param('history_delete_confirmed');

    my $now = DateTime->now->strftime('%F');
    foreach my $key (
            qw/history.circ.retention_start history.hold.retention_start/) {

        my $val = $self->cgi->param($key);
        if($val and $val eq 'on') {
            # Set the start time to 'now' unless a start time already exists for the user
            $settings{$key} = $now unless $$set_map{$key};

        } else {

            next unless $$set_map{$key}; # nothing to do

            $clear_circ_history = 1 if $key =~ /circ/;
            $clear_hold_history = 1 if $key =~ /hold/;

            if (!$hist_clear_confirmed) {
                # when clearing circ history, only warn if history data exists.

                if ($clear_circ_history) {

                    if ($self->fetch_user_circ_history(0, 1)->[0]) {
                        $hist_warning_needed = 1;
                        next; # no history updates while confirmation pending
                    }

                } else {

                    my $one_hold = $e->json_query({
                        select => {
                            au => [{
                                column => 'id',
                                transform => 'action.usr_visible_holds',
                                result_field => 'id'
                            }]
                        },
                        from => 'au',
                        where => {id => $e->requestor->id},
                        limit => 1
                    })->[0];

                    if ($one_hold) {
                        $hist_warning_needed = 1;
                        next; # no history updates while confirmation pending
                    }
                }
            }

            $settings{$key} = undef;

            if ($key eq 'history.circ.retention_start') {
                # delete existing circulation history data.
                $U->simplereq(
                    'open-ils.actor',
                    'open-ils.actor.history.circ.clear',
                    $self->editor->authtoken);
            }
        }
    }

    # Warn patrons before clearing circ/hold history
    if ($hist_warning_needed) {
        $self->ctx->{clear_circ_history} = $clear_circ_history;
        $self->ctx->{clear_hold_history} = $clear_hold_history;
        $self->ctx->{confirm_history_delete} = 1;
    }

    # Send the modified settings off to be saved
    $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.patron.settings.update',
        $self->editor->authtoken, undef, \%settings);

    $self->ctx->{updated_user_settings} = \%settings;

    if ($use_privacy_waiver) {
        my %waiver;
        my $saved_entries = ();
        my @waiver_types = qw/place_holds pickup_holds checkout_items view_history/;

        # initialize our waiver hash with waiver IDs from hidden input
        # (this ensures that we capture entries with no checked boxes)
        foreach my $waiver_row_id ($self->cgi->param("waiver_id")) {
            $waiver{$waiver_row_id} = {};
        }

        # process our waiver checkboxes into a hash, keyed by waiver ID
        # (a new entry, if any, has id = 'new')
        foreach my $waiver_type (@waiver_types) {
            if ($self->cgi->param("waiver_$waiver_type")) {
                foreach my $waiver_id ($self->cgi->param("waiver_$waiver_type")) {
                    # ensure this waiver exists in our hash
                    $waiver{$waiver_id} = {} if !$waiver{$waiver_id};
                    $waiver{$waiver_id}->{$waiver_type} = 1;
                }
            }
        }

        foreach my $k (keys %waiver) {
            my $w = $waiver{$k};
            # get name from textbox
            $w->{name} = $self->cgi->param("waiver_name_$k");
            $w->{id} = $k;
            foreach (@waiver_types) {
                $w->{$_} = 0 unless ($w->{$_});
            }
            push @$saved_entries, $w;
        }

        # update patron privacy waiver entries
        $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.patron.privacy_waiver.update',
            $self->editor->authtoken, undef, $saved_entries);

        $self->ctx->{updated_waiver_entries} = $saved_entries;
    }

    # re-fetch user prefs
    return $self->_load_user_with_prefs || Apache2::Const::OK;
}

sub load_myopac_prefs_my_lists {
    my $self = shift;

    my @user_prefs = qw/
        opac.lists_per_page
        opac.list_items_per_page
    /;

    my $stat = $self->_load_user_with_prefs;
    return $stat if $stat;

    return Apache2::Const::OK
        unless $self->cgi->request_method eq 'POST';

    my %settings;
    my $set_map = $self->ctx->{user_setting_map};

    foreach my $key (@user_prefs) {
        my $val = $self->cgi->param($key);
        $settings{$key}= $val unless $$set_map{$key} eq $val;
    }

    if (keys %settings) { # we found a different setting value
        # Send the modified settings off to be saved
        $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.patron.settings.update',
            $self->editor->authtoken, undef, \%settings);

        # re-fetch user prefs
        $self->ctx->{updated_user_settings} = \%settings;
        $stat = $self->_load_user_with_prefs;
    }

    return $stat || Apache2::Const::OK;
}

sub fetch_user_holds {
    my $self = shift;
    my $hold_ids = shift;
    my $ids_only = shift;
    my $flesh = shift;
    my $available = shift;
    my $limit = shift;
    my $offset = shift;

    my $e = $self->editor;
    my $all_ids; # to be used below.

    if(!$hold_ids) {
        my $circ = OpenSRF::AppSession->create('open-ils.circ');

        $hold_ids = $circ->request(
            'open-ils.circ.holds.id_list.retrieve.authoritative',
            $e->authtoken,
            $e->requestor->id,
            $available
        )->gather(1);
        $circ->kill_me;

        $all_ids = $hold_ids;
        $hold_ids = [ grep { defined $_ } @$hold_ids[$offset..($offset + $limit - 1)] ] if $limit or $offset;

    } else {
        $all_ids = $hold_ids;
    }

    return { ids => $hold_ids, all_ids => $all_ids } if $ids_only or @$hold_ids == 0;

    my $args = {
        suppress_notices => 1,
        suppress_transits => 1,
        suppress_mvr => 1,
        suppress_patron_details => 1
    };

    # ----------------------------------------------------------------
    # Collect holds in batches of $batch_size for faster retrieval

    my $batch_size = 8;
    my $batch_idx = 0;
    my $mk_req_batch = sub {
        my @ses;
        my $top_idx = $batch_idx + $batch_size;
        while($batch_idx < $top_idx) {
            my $hold_id = $hold_ids->[$batch_idx++];
            last unless $hold_id;
            my $ses = OpenSRF::AppSession->create('open-ils.circ');
            my $req = $ses->request(
                'open-ils.circ.hold.details.retrieve',
                $e->authtoken, $hold_id, $args);
            push(@ses, {ses => $ses, req => $req});
        }
        return @ses;
    };

    my $first = 1;
    my(@collected, @holds, @ses);

    while(1) {
        @ses = $mk_req_batch->() if $first;
        last if $first and not @ses;

        if(@collected) {
            while(my $blob = pop(@collected)) {
                my @data;

                # in the holds edit UI, we need to know what formats and
                # languages the user selected for this hold, plus what
                # formats/langs are available on the MR as a whole.
                if ($blob->{hold}{hold}->hold_type eq 'M') {
                    my $hold = $blob->{hold}->{hold};

                    # for MR, fetch the combined MR unapi blob
                    (undef, @data) = $self->get_records_and_facets(
                        [$hold->target], undef, {flesh => '{mra}', metarecord => 1});

                    my $filter_org = $U->org_unit_ancestor_at_depth(
                        $hold->selection_ou,
                        $hold->selection_depth);

                    my $filter_data = $U->simplereq(
                        'open-ils.circ',
                        'open-ils.circ.mmr.holds.filters.authoritative.atomic',
                        $hold->target, $filter_org, [$hold->id]
                    );

                    $blob->{metarecord_filters} =
                        $filter_data->[0]->{metarecord};
                    $blob->{metarecord_selected_filters} =
                        $filter_data->[1]->{hold};
                } else {

                    (undef, @data) = $self->get_records_and_facets(
                        [$blob->{hold}->{bre_id}], undef, {flesh => '{mra}'}
                    );
                }

                $blob->{marc_xml} = $data[0]->{marc_xml};
                push(@holds, $blob);
            }
        }

        for my $req_data (@ses) {
            push(@collected, {hold => $req_data->{req}->gather(1)});
            $req_data->{ses}->kill_me;
        }

        @ses = $mk_req_batch->();
        last unless @collected or @ses;
        $first = 0;
    }

    # put the holds back into the original server sort order
    my @sorted;
    for my $id (@$hold_ids) {
        push @sorted, grep { $_->{hold}->{hold}->id == $id } @holds;
    }

    my $curbsides = [];
    try { # if the service is not running, just let this fail silently
        $curbsides = $U->simplereq(
            'open-ils.curbside',
            'open-ils.curbside.fetch_mine.atomic',
            $e->authtoken
        );
    } catch Error with {};

    return { holds => \@sorted, ids => $hold_ids, all_ids => $all_ids, curbsides => $curbsides };
}

sub load_current_curbside_libs {
    my $self = shift;
    my $ctx = $self->ctx;
    my $e = $self->editor;
    my $holds = $e->search_action_hold_request({
        usr              => $e->requestor->id,
        shelf_time       => { '!=' => undef },
        cancel_time      => undef,
        fulfillment_time => undef
    });

    my %pickup_libs;
    for my $h (@$holds) {
        next if ($h->pickup_lib != $h->current_shelf_lib);
        $pickup_libs{$h->pickup_lib} = 1;
    }

    my @curbside_pickup_libs;
    for my $pul (keys %pickup_libs) {
        push(@curbside_pickup_libs, $pul) if $ctx->{get_org_setting}->($pul, 'circ.curbside');
    }

    $ctx->{curbside_pickup_libs} = [
        sort { $U->find_org($U->get_org_tree,$a)->name cmp $U->find_org($U->get_org_tree,$b)->name } @curbside_pickup_libs
    ];
}

sub handle_hold_update {
    my $self = shift;
    my $action = shift;
    my $hold_ids = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $url;

    my @hold_ids = ($hold_ids) ? @$hold_ids : $self->cgi->param('hold_id'); # for non-_all actions
    @hold_ids = @{$self->fetch_user_holds(undef, 1)->{ids}} if $action =~ /_all/;

    my $circ = OpenSRF::AppSession->create('open-ils.circ');

    if($action =~ /cancel/) {

        for my $hold_id (@hold_ids) {
            my $resp = $circ->request(
                'open-ils.circ.hold.cancel', $e->authtoken, $hold_id, 6 )->gather(1); # 6 == patron-cancelled-via-opac
        }

    } elsif ($action =~ /activate|suspend/) {

        my $vlist = [];
        for my $hold_id (@hold_ids) {
            my $vals = {id => $hold_id};

            if($action =~ /activate/) {
                $vals->{frozen} = 'f';
                $vals->{thaw_date} = undef;

            } elsif($action =~ /suspend/) {
                $vals->{frozen} = 't';
                # $vals->{thaw_date} = TODO;
            }
            push(@$vlist, $vals);
        }

        my $resp = $circ->request('open-ils.circ.hold.update.batch.atomic', $e->authtoken, undef, $vlist)->gather(1);
        $self->ctx->{hold_suspend_post_capture} = 1 if
            grep {$U->event_equals($_, 'HOLD_SUSPEND_AFTER_CAPTURE')} @$resp;

    } elsif ($action eq 'edit') {

        my @vals = map {
            my $val = {"id" => $_};
            $val->{"frozen"} = $self->cgi->param("frozen");
            $val->{"pickup_lib"} = $self->cgi->param("pickup_lib");
            $val->{"email_notify"} = $self->cgi->param("email_notify") ? 1 : 0;
            $val->{"phone_notify"} = $self->cgi->param("phone_notify");
            $val->{"sms_notify"} = ( $self->cgi->param("sms_notify") eq '' ) ? undef : $self->cgi->param("sms_notify");
            $val->{"sms_carrier"} = int($self->cgi->param("sms_carrier")) if $val->{"sms_notify"};

            for my $field (qw/expire_time thaw_date/) {
                # XXX TODO make this support other date formats, not just
                # MM/DD/YYYY.
                # Added support for YYYY-MM-DD format as well
                if ($self->cgi->param($field) =~ m:^(\d{2})/(\d{2})/(\d{4})$:) {
                    $val->{$field} = "$3-$1-$2";
                } elsif ($self->cgi->param($field) =~ m:^(\d{4})-(\d{2})-(\d{2})$:) {
                    $val->{$field} = $self->cgi->param($field);
                } else {
                    $logger->warn("ignoring invalid date field when updating hold request");
                }
            }

            $val->{holdable_formats} = # no-op for non-MR holds
                $self->compile_holdable_formats(undef, $_);

            $val;
        } @hold_ids;

        $circ->request(
            'open-ils.circ.hold.update.batch.atomic',
            $e->authtoken, undef, \@vals
        )->gather(1);   # LFW XXX test for failure
        $url = $self->ctx->{proto} . '://' . $self->ctx->{hostname} . $self->ctx->{opac_root} . '/myopac/holds';
        foreach my $param (('loc', 'qtype', 'query')) {
            if ($self->cgi->param($param)) {
                my @vals = $self->cgi->param($param);
                $url .= ";$param=" . uri_escape_utf8($_) foreach @vals;
            }
        }
    } elsif ($action eq 'curbside') { # we'll only work on one curbside slot per refresh
        $circ->kill_me;

        $circ = OpenSRF::AppSession->create('open-ils.curbside');

        # see what we're doing with curbside here...
        my $cs_action = $self->cgi->param("cs_action");
        my $slot_id = $self->cgi->param("cs_slot_id");

        # we have an id, let's grab it if we can
        my $slot = $e->retrieve_action_curbside($slot_id);
        $slot = undef if ($slot && $slot->patron != $e->requestor->id); # nice try!

        my $org = $self->cgi->param("cs_org");
        my $date = $self->cgi->param("cs_date");
        my $time = $self->cgi->param("cs_time");
        my $notes = $self->cgi->param("cs_notes");

        if ($slot) {
            $org ||= $slot->org;
            $notes ||= $slot->notes;
            if ($slot->slot) {
                my $dt = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($slot->slot));
                $date ||= $dt->strftime('%F');
                $time ||= $dt->strftime('%T');
            }
        }

        $ctx->{cs_org} = $org;
        $ctx->{cs_date} = $date;
        $ctx->{cs_time} = $time;
        $ctx->{cs_notes} = $notes;
        $ctx->{cs_slot_id} = $slot->id if ($slot);
        $ctx->{cs_slot} = $slot;

        if ($cs_action eq 'reset') {
            $ctx->{cs_org} = $org = undef;
            $ctx->{cs_date} = $date = undef;
            $ctx->{cs_time} = $time = undef;
            $ctx->{cs_notes} = $notes = undef;
            $ctx->{cs_slot_id} = $slot_id = undef;
            $ctx->{cs_slot} = $slot = undef;
        } elsif ($cs_action eq 'save' && $org && $date && $time) {
            my $mode = $slot ? 'update' : 'create';
            $slot = $circ->request(
                "open-ils.curbside.${mode}_appointment",
                $e->authtoken, $e->requestor->id, $date, $time, $org, $notes
            )->gather(1);

            if (defined $U->event_code($slot)) {
                $self->apache->log->warn(
                    "error attempting to $mode a curbside appointment for patron ".
                    $e->requestor->id . ", got event " .  $slot->{textcode}
                );
                $ctx->{curbside_action_event} = $slot;
                $ctx->{cs_slot} = undef;
            } else {
                $ctx->{cs_slot} = $slot;
            }
            $url = $self->ctx->{proto} . '://' . $self->ctx->{hostname} . $self->ctx->{opac_root} . '/myopac/holds_curbside';
        } elsif ($cs_action eq 'cancel' && $slot) {
            my $curbsides = $U->simplereq(
                'open-ils.curbside',
                'open-ils.curbside.delete_appointment',
                $e->authtoken, $slot->id
            );
            $url = $self->ctx->{proto} . '://' . $self->ctx->{hostname} . $self->ctx->{opac_root} . '/myopac/holds_curbside';
        } elsif ($cs_action eq 'arrive' && $slot) {
            my $curbsides = $U->simplereq(
                'open-ils.curbside',
                'open-ils.curbside.mark_arrived',
                $e->authtoken, $slot->id
            );
        } elsif ($cs_action eq 'deliver' && $slot) {
            my $curbsides = $U->simplereq(
                'open-ils.curbside',
                'open-ils.curbside.mark_delivered',
                $e->authtoken, $slot->id
            );
        }

        if ($date and $org and !$ctx->{cs_times}{$org}{$date}) {
            $ctx->{cs_times}{$org}{$date} = $circ->request(
                'open-ils.curbside.times_for_date.atomic',
                $e->authtoken, $date, $org
            )->gather(1);
        }
    }

    $circ->kill_me;
    return defined($url) ? $self->generic_redirect($url) : undef;
}

sub load_myopac_holds {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    my $limit = $self->cgi->param('limit') || 15;
    my $offset = $self->cgi->param('offset') || 0;
    my $action = $self->cgi->param('action') || '';
    my $hold_id = $self->cgi->param('hid');
    my $available = int($self->cgi->param('available') || 0);

    my $hold_handle_result;
    $hold_handle_result = $self->handle_hold_update($action) if $action;

    my $holds_object;
    if ($self->cgi->param('sort') ne "") {
        $holds_object = $self->fetch_user_holds($hold_id ? [$hold_id] : undef, 0, 1, $available);
    }
    else {
        $holds_object = $self->fetch_user_holds($hold_id ? [$hold_id] : undef, 0, 1, $available, $limit, $offset);
    }

    if($holds_object->{holds}) {
        $ctx->{holds} = $holds_object->{holds};
        $ctx->{curbside_appointments} = {};

        $logger->info('curbside: found '.scalar(@{$holds_object->{curbsides}}).' appointments');

        for my $cs (@{$holds_object->{curbsides}}) {
            if ($cs->slot) {
                my $dt = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($cs->slot))->strftime('%F');
                $ctx->{cs_times}{$cs->org}{$dt} = $U->simplereq(
                    'open-ils.curbside', 'open-ils.curbside.times_for_date.atomic',
                    $e->authtoken, $dt, $cs->org
                );
            }
            $ctx->{curbside_appointments}{$cs->org} = $cs;
        }
    }
    $ctx->{holds_ids} = $holds_object->{all_ids};
    $ctx->{holds_limit} = $limit;
    $ctx->{holds_offset} = $offset;

    return defined($hold_handle_result) ? $hold_handle_result : Apache2::Const::OK;
}

sub load_myopac_hold_subscriptions {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    my $sub_remove = $self->cgi->param('remove');

    if ($sub_remove and $ctx->{user}->id) {
        my $sub_entries = $self->editor->search_container_user_bucket_item(
            { bucket => $sub_remove, target_user => $ctx->{user}->id }
        );

        $self->editor->xact_begin;
        $self->editor->delete_container_user_bucket_item($_) for @$sub_entries;
        $self->editor->xact_commit;

        return $self->generic_redirect(
            $self->ctx->{proto} . '://' . $self->ctx->{hostname} . $self->ctx->{opac_root} . '/myopac/hold_subscriptions'
        );
    }

    return Apache2::Const::OK;
}

my $data_filler;

sub load_place_hold {
    my $self = shift;
    my $ctx = $self->ctx;
    my $gos = $ctx->{get_org_setting};
    my $e = $self->editor;
    my $cgi = $self->cgi;

    $self->ctx->{page} = 'place_hold';
    my @targets = uniq $cgi->param('hold_target');
    my @parts = $cgi->param('part');

    $ctx->{hold_subscription} = $cgi->param('hold_subscription');
    $ctx->{hold_type} = $cgi->param('hold_type');
    $ctx->{default_pickup_lib} = $e->requestor->home_ou; # unless changed below
    $ctx->{email_notify} = $cgi->param('email_notify');
    if ($cgi->param('phone_notify_checkbox')) {
        $ctx->{phone_notify} = $cgi->param('phone_notify');
    }
    if ($cgi->param('sms_notify_checkbox')) {
        $ctx->{sms_notify} = $cgi->param('sms_notify');
        $ctx->{sms_carrier} = $cgi->param('sms_carrier');
    }

    return $self->generic_redirect unless @targets;

    # Check for multiple hold placement via the num_copies widget.
    my $num_copies = int($cgi->param('num_copies')); # if undefined, we get 0.
    if ($num_copies > 1) {
        # Only if we have 1 hold target and no parts.
        if (scalar(@targets) == 1 && !$parts[0]) {
            # Also, only for M and T holds.
            if ($ctx->{hold_type} eq 'M' || $ctx->{hold_type} eq 'T') {
                # Add the extra holds to @targets. NOTE: We start with
                # 1 and go to < $num_copies to account for the
                # existing target.
                for (my $i = 1; $i < $num_copies; $i++) {
                    push(@targets, $targets[0]);
                }
            }
        }
    }

    $logger->info("Looking at hold_type: " . $ctx->{hold_type} . " and targets: @targets");

    $ctx->{any_part_label} = $ctx->{get_i18n_string}->(1, 'All Parts');
    $ctx->{staff_recipient} = $self->editor->retrieve_actor_user([
        $e->requestor->id,
        {
            flesh => 1,
            flesh_fields => {
                au => ['settings', 'card']
            }
        }
    ]) or return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    my $user_setting_map = {
        map { $_->name => OpenSRF::Utils::JSON->JSON2perl($_->value) }
            @{
                $ctx->{staff_recipient}->settings
            }
    };
    $ctx->{user_setting_map} = $user_setting_map;

    my $default_notify = (defined $$user_setting_map{'opac.hold_notify'} ? $$user_setting_map{'opac.hold_notify'} : 'email:phone');
    if ($default_notify =~ /email/) {
        $ctx->{default_email_notify} = 'checked';
    } else {
        $ctx->{default_email_notify} = '';
    }
    if ($default_notify =~ /phone/) {
        $ctx->{default_phone_notify} = 'checked';
    } else {
        $ctx->{default_phone_notify} = '';
    }
    if ($default_notify =~ /sms/) {
        $ctx->{default_sms_notify} = 'checked';
    } else {
        $ctx->{default_sms_notify} = '';
    }
    if ($cgi->param('hold_suspend')) {
        $ctx->{frozen} = 1;
        # TODO: Make this support other date formats, not just mm/dd/yyyy.
        # We should use a date input type on the forms once it is supported by Firefox.
        # I didn't do that now because it is not available in a general release.

        # Update - I added a second format to support duet-date-picker
        if ($cgi->param('thaw_date') =~ m:^(\d{2})/(\d{2})/(\d{4})$:){
            eval {
                my $dt = DateTime::Format::ISO8601->parse_datetime("$3-$1-$2");
                $ctx->{thaw_date} = $dt->ymd;
            };
        } elsif ($cgi->param('thaw_date') =~ m:^(\d{4})-(\d{2})-(\d{2})$:){
            eval {
                my $dt = DateTime::Format::ISO8601->parse_datetime("$1-$2-$3");
                $ctx->{thaw_date} = $dt->ymd;
            };
        } else {
            $logger->warn("ignoring invalid thaw_date when placing hold request");
        }
    }


    # If we have a default pickup location, grab it
    if ($$user_setting_map{'opac.default_pickup_location'}) {
        $ctx->{default_pickup_lib} = $$user_setting_map{'opac.default_pickup_location'};
    }

    my $request_lib = $e->requestor->ws_ou;
    my @hold_data;
    $ctx->{hold_data} = \@hold_data;

    $data_filler = sub {
        my $hdata = shift;
        if ($ctx->{email_notify}) { $hdata->{email_notify} = $ctx->{email_notify}; }
        if ($ctx->{phone_notify}) { $hdata->{phone_notify} = $ctx->{phone_notify}; }
        if ($ctx->{sms_notify}) { $hdata->{sms_notify} = $ctx->{sms_notify}; }
        if ($ctx->{sms_carrier}) { $hdata->{sms_carrier} = $ctx->{sms_carrier}; }
        if ($ctx->{frozen}) { $hdata->{frozen} = 1; }
        if ($ctx->{thaw_date}) { $hdata->{thaw_date} = $ctx->{thaw_date}; }
        return $hdata;
    };

    my $type_dispatch = {
        M => sub {
            # target metarecords
            my $mrecs = $e->batch_retrieve_metabib_metarecord([
                \@targets,
                {flesh => 1, flesh_fields => {mmr => ['master_record']}}],
                {substream => 1}
            );

            for my $id (@targets) {
                my ($mr) = grep {$_->id eq $id} @$mrecs;

                my $ou_id = $cgi->param('pickup_lib') || $self->ctx->{search_ou};
                my $filter_data = $U->simplereq(
                    'open-ils.circ',
                    'open-ils.circ.mmr.holds.filters.authoritative', $mr->id, $ou_id);

                my $holdable_formats =
                    $self->compile_holdable_formats($mr->id);

                push(@hold_data, $data_filler->({
                    target => $mr,
                    record => $mr->master_record,
                    holdable_formats => $holdable_formats,
                    metarecord_filters => $filter_data->{metarecord}
                }));
            }
        },
        T => sub {
            my $recs = $e->batch_retrieve_biblio_record_entry(
                [\@targets,  {flesh => 1, flesh_fields => {bre => ['metarecord']}}],
                {substream => 1}
            );

            for my $id (@targets) { # force back into the correct order
                my ($rec) = grep {$_->id eq $id} @$recs;

                # NOTE: if tpac ever supports locked-down pickup libs,
                # we'll need to pass a pickup_lib param along with the
                # record to filter the set of monographic parts.
                my $parts = $U->simplereq(
                    'open-ils.search',
                    'open-ils.search.biblio.record_hold_parts',
                    {record => $rec->id}
                );

                # T holds on records that have parts are normally OK, but if the record has
                # no non-part copies, the hold will ultimately fail.  When that happens,
                # require the user to select a part.
                #
                # If the global flag circ.holds.api_require_monographic_part_when_present is
                # enabled, or the library setting circ.holds.ui_require_monographic_part_when_present
                # is active for any item owning library associated with the bib, then any configured
                # parts for the bib is enough to disallow title holds (aka require part selection).
                my $part_required = 0;
                if (@$parts) {
                    $part_required = $ctx->{part_required_when_present_global_flag};
                    if (!$part_required) {
                        my $resp = $e->json_query({
                            select => {
                                acn => ['owning_lib']
                            },
                            from => {acn => {acp => {type => 'left'}}},
                            where => {
                                '+acp' => {
                                    '-or' => [
                                        {deleted => 'f'},
                                        {id => undef} # left join
                                    ]
                                },
                                '+acn' => {deleted => 'f', record => $rec->id}
                            },
                            distinct => 't'
                        });
                        my $org_ids = [map {$_->{owning_lib}} @$resp];
                        foreach my $org (@$org_ids) { # FIXME: worth shortcutting/optimizing?
                            if ($self->ctx->{get_org_setting}->($org, 'circ.holds.ui_require_monographic_part_when_present')) {
                                $part_required = 1;
                            }
                        }
                    }
                    if (!$part_required) {
                        my $np_copies = $e->json_query({
                            select => { acp => [{column => 'id', transform => 'count', alias => 'count'}]},
                            from => {acp => {acn => {}, acpm => {type => 'left'}}},
                            where => {
                                '+acp' => {deleted => 'f'},
                                '+acn' => {deleted => 'f', record => $rec->id},
                                '+acpm' => {id => undef}
                            }
                        });
                        $part_required = 1 if $np_copies->[0]->{count} == 0;
                    }
                }

                push(@hold_data, $data_filler->({
                    target => $rec,
                    record => $rec,
                    parts => $parts,
                    part_required => $part_required
                }));
            }
        },
        V => sub {
            my $vols = $e->batch_retrieve_asset_call_number([
                \@targets, {
                    "flesh" => 1,
                    "flesh_fields" => {"acn" => ["record"]}
                }
            ], {substream => 1});

            for my $id (@targets) {
                my ($vol) = grep {$_->id eq $id} @$vols;
                push(@hold_data, $data_filler->({target => $vol, record => $vol->record}));
            }
        },
        C => sub {
            my $copies = $e->batch_retrieve_asset_copy([
                \@targets, {
                    "flesh" => 2,
                    "flesh_fields" => {
                        "acn" => ["record"],
                        "acp" => ["call_number"]
                    }
                }
            ], {substream => 1});

            for my $id (@targets) {
                my ($copy) = grep {$_->id eq $id} @$copies;
                push(@hold_data, $data_filler->({target => $copy, record => $copy->call_number->record}));
            }
        },
        I => sub {
            my $isses = $e->batch_retrieve_serial_issuance([
                \@targets, {
                    "flesh" => 2,
                    "flesh_fields" => {
                        "siss" => ["subscription"], "ssub" => ["record_entry"]
                    }
                }
            ], {substream => 1});

            for my $id (@targets) {
                my ($iss) = grep {$_->id eq $id} @$isses;
                push(@hold_data, $data_filler->({target => $iss, record => $iss->subscription->record_entry}));
            }
        }
        # ...

    }->{$ctx->{hold_type}}->();

    # caller sent bad target IDs or the wrong hold type
    return Apache2::Const::HTTP_BAD_REQUEST unless @hold_data;

    # generate the MARC xml for each record
    $_->{marc_xml} = XML::LibXML->new->parse_string($_->{record}->marc) for @hold_data;

    my $pickup_lib = $cgi->param('pickup_lib');
    # no pickup lib means no holds placement, except for subscriptions
    return Apache2::Const::OK unless $pickup_lib || $ctx->{hold_subscription};

    $ctx->{hold_attempt_made} = 1;

    # Give the original CGI params back to the user in case they
    # want to try to override something.
    $ctx->{orig_params} = $cgi->Vars;
    delete $ctx->{orig_params}{submit};
    delete $ctx->{orig_params}{hold_target};
    delete $ctx->{orig_params}{part};

    my $usr = $e->requestor->id;

    if ($ctx->{is_staff}) {
        $logger->info("Staff initiated hold");
        if (!$cgi->param("hold_usr_is_requestor")) {
            # find the real hold target

            $usr = $U->simplereq(
                'open-ils.actor',
                "open-ils.actor.user.retrieve_id_by_barcode_or_username",
                $e->authtoken, $cgi->param("hold_usr"));

            if (defined $U->event_code($usr)) {
                $ctx->{hold_failed} = 1;
                $ctx->{hold_failed_event} = $usr;
            }
        }

        if ($ctx->{hold_subscription}) {
            # this is a batch event, hold "user" is a bucket id
            $logger->info("Hold Group Event requested for user bucket: " . $ctx->{hold_subscription});
            $usr = $e->retrieve_container_user_bucket($ctx->{hold_subscription});
        }
    }

    # target_id is the true target_id for holds placement.
    # needed for attempt_hold_placement()
    # With the exception of P-type holds, target_id == target->id.
    $_->{target_id} = $_->{target}->id for @hold_data;

    if ($ctx->{hold_type} eq 'T') {

        # Much like quantum wave-particles, P-type holds pop into
        # and out of existence at the user's whim.  For our purposes,
        # we treat such holds as T(itle) holds with a selected_part
        # designation.  When the time comes to pass the hold information
        # off for holds possibility testing and placement, make it look
        # like a real P-type hold.
        my (@p_holds, @t_holds);

        # Now that we have the num_copies field for mutliple title and
        # metarecord hold placement, the number of holds and parts
        # arrays can get out of sync.  We only want to parse out parts
        # if the numbers are equal.
        if ($#hold_data == $#parts) {
            for my $idx (0..$#parts) {
                my $hdata = $hold_data[$idx];
                if (my $part = $parts[$idx]) {
                    $hdata->{target_id} = $part;
                    $hdata->{selected_part} = $part;
                    push(@p_holds, $hdata);
                } else {
                    push(@t_holds, $hdata);
                }
            }
        } else {
            @t_holds = @hold_data;
        }

        $self->apache->log->warn("$#parts : @t_holds");

        $self->attempt_hold_placement($usr, $pickup_lib, 'P', @p_holds) if @p_holds;
        $self->attempt_hold_placement($usr, $pickup_lib, 'T', @t_holds) if @t_holds;

    } else {
        $self->attempt_hold_placement($usr, $pickup_lib, $ctx->{hold_type}, @hold_data);
    }

    # NOTE: we are leaving the staff-placed patron barcode cookie
    # in place.  Otherwise, it's not possible to place more than
    # one hold for the patron within a staff/patron session.  This
    # does leave the barcode to linger longer than is ideal, but
    # normal staff work flow will cause the cookie to be replaced
    # with each new patron anyway.
    # TODO: See about getting the staff client to clear the cookie

    # return to the place_hold page so the results of the hold
    # placement attempt can be reported to the user
    return Apache2::Const::OK;
}

sub attempt_hold_placement {
    my ($self, $usr, $pickup_lib, $hold_type, @hold_data) = @_;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;
    my $e = $self->editor;

    my $user_container = undef;
    if (ref($usr)) { # $usr is actually a container for a subscription...
        $user_container = $usr->id;
        return unless ($hold_type eq 'T'); # Only T-hold subscriptions for now.
    }

    # First see if we should warn/block for any holds that
    # might have locally available items for non-subscriptions.
    if (!$user_container) {
        for my $hdata (@hold_data) {
            my ($local_block, $local_alert) = $self->local_avail_concern(
                $hdata->{target_id}, $hold_type, $pickup_lib);

            if ($local_block) {
                $hdata->{hold_failed} = 1;
                $hdata->{hold_local_block} = 1;
            } elsif ($local_alert) {
                $hdata->{hold_failed} = 1;
                $hdata->{hold_local_alert} = 1;
            }
        }
    }

    my $method = $user_container
        ? 'open-ils.circ.holds.test_and_create.subscription_batch'
        : 'open-ils.circ.holds.test_and_create.batch';

    if ($cgi->param('override')) {
        $method .= '.override';

    } elsif (!$ctx->{is_staff})  {

        $method .= '.override' if $self->ctx->{get_org_setting}->(
            $e->requestor->home_ou, "opac.patron.auto_overide_hold_events");
    }

    my @create_targets = map {$_->{target_id}} (grep { !$_->{hold_failed} } @hold_data);


    if(@create_targets) {

        # holdable formats may be different for each MR hold.
        # map each set to the ID of the target.
        my $holdable_formats = {};
        if ($hold_type eq 'M') {
            $holdable_formats->{$_->{target_id}} =
                $_->{holdable_formats} for @hold_data;
        }

        my $bses = OpenSRF::AppSession->create('open-ils.circ');

        my @create_params = ();

        if ($user_container) {
            @create_params = (
                $data_filler->({
                    hold_type => $hold_type,
                    holdable_formats_map => $holdable_formats, # currently always unset, only T holds
                }),
                $user_container,
                $create_targets[0],
            );
        } else {
            @create_params = (
                $data_filler->({
                    patronid => $usr,
                    pickup_lib => $pickup_lib,
                    hold_type => $hold_type,
                    holdable_formats_map => $holdable_formats,
                }),
                \@create_targets
            );
        }

        my $breq = $bses->request($method, $e->authtoken, @create_params);

        while (my $resp = $breq->recv) {

            $resp = $resp->content;
            $logger->info('batch hold placement result: ' . OpenSRF::Utils::JSON->perl2JSON($resp));

            if ($U->event_code($resp)) {
                $ctx->{general_hold_error} = $resp;
                last;
            }

            # subscription batch create sends an initial response to assist with client-side counting
            next if (
                $user_container and
                defined($$resp{count}) and $$resp{count} == 0
                and defined($$resp{total}) and $$resp{total} > 0
            );

            # Skip those that had the hold_success or hold_failed fields set for duplicate holds placement.
            my ($hdata) = grep {$_->{target_id} eq $resp->{target} && !($_->{hold_failed} || $_->{hold_success})} @hold_data;
            my $result = $resp->{result};

            if ($U->event_code($result)) {
                # e.g. permission denied
                $hdata->{hold_failed} = 1;
                $hdata->{hold_failed_event} = $result;

            } else {

                if(not ref $result and $result > 0) {
                    # successul hold returns the hold ID
                    $hdata->{hold_success} = $result;

                } else {
                    # hold-specific failure event
                    $hdata->{hold_failed} = 1;

                    if (ref $result eq 'HASH') {
                        $hdata->{hold_failed_event} = $result->{last_event};

                        if ($result->{age_protected_copy}) {
                            my %temp = %{$hdata->{hold_failed_event}};
                            my $theTextcode = $temp{"textcode"};
                            $theTextcode.=".override";
                            $hdata->{could_override} = $self->editor->allowed( $theTextcode );
                            $hdata->{age_protect} = 1;
                        } else {
                            $hdata->{could_override} = $result->{place_unfillable} ||
                                $self->test_could_override($hdata->{hold_failed_event});
                        }
                    } elsif (ref $result eq 'ARRAY') {
                        $hdata->{hold_failed_event} = $result->[0];

                        if ($result->[3]) { # age_protect_only
                            my %temp = %{$hdata->{hold_failed_event}};
                            my $theTextcode = $temp{"textcode"};
                            $theTextcode.=".override";
                            $hdata->{could_override} = $self->editor->allowed( $theTextcode );
                            $hdata->{age_protect} = 1;
                        } else {
                            $hdata->{could_override} = $result->[4] || # place_unfillable
                                $self->test_could_override($hdata->{hold_failed_event});
                        }
                    }
                }
            }
        }

        $bses->kill_me;
    }

    if ($self->cgi->param('clear_cart')) {
        $self->clear_anon_cache;
    }
}

# pull the selected formats and languages for metarecord holds
# from the CGI params and map them into the JSON holdable
# formats...er, format.
# if no metarecord is provided, we'll pull it from the target
# of the provided hold.
sub compile_holdable_formats {
    my ($self, $mr_id, $hold_id) = @_;
    my $e = $self->editor;
    my $cgi = $self->cgi;

    # exit early if not needed
    return undef unless
        grep /metarecord_formats_|metarecord_langs_/,
        $cgi->param;

    # CGI params are based on the MR id, since during hold placement
    # we have no old ID.  During hold edit, map the hold ID back to
    # the metarecod target.
    $mr_id =
        $e->retrieve_action_hold_request($hold_id)->target
        unless $mr_id;

    my $format_attr = $self->ctx->{get_cgf}->(
        'opac.metarecord.holds.format_attr');

    if (!$format_attr) {
        $logger->error("Missing config.global_flag: ".
            "opac.metarecord.holds.format_attr!");
        return "";
    }

    $format_attr = $format_attr->value;

    # during hold placement or edit submission, the user selects
    # which of the available formats/langs are acceptable.
    # Capture those here as the holdable_formats for the MR hold.
    my @selected_formats = $cgi->param("metarecord_formats_$mr_id");
    my @selected_langs = $cgi->param("metarecord_langs_$mr_id");

    # map the selected attrs into the JSON holdable_formats structure
    my $blob = {};
    if (@selected_formats) {
        $blob->{0} = [
            map { {_attr => $format_attr, _val => $_} }
            @selected_formats
        ];
    }
    if (@selected_langs) {
        $blob->{1} = [
            map { {_attr => 'item_lang', _val => $_} }
            @selected_langs
        ];
    }

    return OpenSRF::Utils::JSON->perl2JSON($blob);
}

sub fetch_user_circs {
    my $self = shift;
    my $flesh = shift; # flesh bib data, etc.
    my $circ_ids = shift;
    my $limit = shift;
    my $offset = shift;

    my $e = $self->editor;

    my @circ_ids;

    if($circ_ids) {
        @circ_ids = @$circ_ids;

    } else {

        my $query = {
            select => {circ => ['id']},
            from => 'circ',
            where => {
                '+circ' => {
                    usr => $e->requestor->id,
                    checkin_time => undef,
                    '-or' => [
                        {stop_fines => undef},
                        {stop_fines => {'not in' => ['LOST','CLAIMSRETURNED','LONGOVERDUE']}}
                    ],
                }
            },
            order_by => {circ => ['due_date']}
        };

        $query->{limit} = $limit if $limit;
        $query->{offset} = $offset if $offset;

        my $ids = $e->json_query($query);
        @circ_ids = map {$_->{id}} @$ids;
    }

    return [] unless @circ_ids;

    my $qflesh = {
        flesh => 3,
        flesh_fields => {
            circ => ['target_copy'],
            acp => ['call_number','parts'],
            acn => ['record','owning_lib','prefix','suffix']
        }
    };

    $e->xact_begin;
    my $circs = $e->search_action_circulation(
        [{id => \@circ_ids}, ($flesh) ? $qflesh : {}], {substream => 1});

    my @circs;
    for my $circ (@$circs) {
        push(@circs, {
            circ => $circ,
            marc_xml => ($flesh and $circ->target_copy->call_number->id != -1) ?
                XML::LibXML->new->parse_string($circ->target_copy->call_number->record->marc) :
                undef  # pre-cat copy, use the dummy title/author instead
        });
    }
    $e->rollback;

    # make sure the final list is in the correct order
    my @sorted_circs;
    for my $id (@circ_ids) {
        push(
            @sorted_circs,
            (grep { $_->{circ}->id == $id } @circs)
        );
    }

    return \@sorted_circs;
}


sub handle_circ_renew {
    my $self = shift;
    my $action = shift;
    my $ctx = $self->ctx;

    my @renew_ids = $self->cgi->param('circ');

    my $circs = $self->fetch_user_circs(0, ($action eq 'renew') ? [@renew_ids] : undef);

    # TODO: fire off renewal calls in batches to speed things up
    my @responses;
    for my $circ (@$circs) {

        my $evt = $U->simplereq(
            'open-ils.circ',
            'open-ils.circ.renew',
            $self->editor->authtoken,
            {
                patron_id => $self->editor->requestor->id,
                copy_id => $circ->{circ}->target_copy,
                opac_renewal => 1
            }
        );

        # TODO return these, then insert them into the circ data
        # blob that is shoved into the template for each circ
        # so the template won't have to match them
        push(@responses, {copy => $circ->{circ}->target_copy, evt => $evt});
    }

    return @responses;
}

sub load_myopac_circs {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    $ctx->{circs} = [];
    my $limit = $self->cgi->param('limit') || 0; # 0 == unlimited
    my $offset = $self->cgi->param('offset') || 0;
    my $action = $self->cgi->param('action') || '';

    # perform the renewal first if necessary
    my @results = $self->handle_circ_renew($action) if $action =~ /renew/;

    $ctx->{circs} = $self->fetch_user_circs(1, undef, $limit, $offset);

    my $success_renewals = 0;
    my $failed_renewals = 0;
    for my $data (@{$ctx->{circs}}) {
        my ($resp) = grep { $_->{copy} == $data->{circ}->target_copy->id } @results;

        if($resp) {
            my $evt = ref($resp->{evt}) eq 'ARRAY' ? $resp->{evt}->[0] : $resp->{evt};

            # extract the fail_part, if present, from the event payload;
            # since # the payload is an acp object in some cases,
            # blindly looking for a # 'fail_part' key in the template can
            # break things
            $evt->{fail_part} = (ref($evt->{payload}) eq 'HASH' && exists $evt->{payload}->{fail_part}) ?
                $evt->{payload}->{fail_part} :
                '';

            $data->{renewal_response} = $evt;
            $success_renewals++ if $evt->{textcode} eq 'SUCCESS';
            $failed_renewals++ if $evt->{textcode} ne 'SUCCESS';
        }
    }

    $ctx->{success_renewals} = $success_renewals;
    $ctx->{failed_renewals} = $failed_renewals;

    return Apache2::Const::OK;
}

sub load_myopac_circ_history {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $limit = $self->cgi->param('limit') || 15;
    my $offset = $self->cgi->param('offset') || 0;
    my $action = $self->cgi->param('action') || '';

    my $circ_handle_result;
    $circ_handle_result = $self->handle_circ_update($action) if $action;

    $ctx->{circ_history_limit} = $limit;
    $ctx->{circ_history_offset} = $offset;

    # Defer limitation to circ_history.tt2 when sorting
    if ($self->cgi->param('sort')) {
        $limit = undef;
        $offset = undef;
    }

    $ctx->{circs} = $self->fetch_user_circ_history(1, $limit, $offset);
    return Apache2::Const::OK;
}

# if 'flesh' is set, copy data etc. is loaded and the return value is
# a hash of 'circ' and 'marc_xml'.  Othwerwise, it's just a list of
# auch objects.
sub fetch_user_circ_history {
    my ($self, $flesh, $limit, $offset) = @_;
    my $e = $self->editor;

    my %limits = ();
    $limits{offset} = $offset if defined $offset;
    $limits{limit} = $limit if defined $limit;

    my %flesh_ops = (
        flesh => 3,
        flesh_fields => {
            auch => ['target_copy','source_circ'],
            acp => ['call_number','parts'],
            acn => ['record','prefix','suffix']
        },
    );

    $e->xact_begin;
    my $circs = $e->search_action_user_circ_history(
        [
            {usr => $e->requestor->id},
            {   # order newest to oldest by default
                order_by => {auch => 'xact_start DESC'},
                $flesh ? %flesh_ops : (),
                %limits
            }
        ],
        {substream => 1}
    );
    $e->rollback;

    return $circs unless $flesh;

    $e->xact_begin;
    my @circs;
    my %unapi_cache = ();
    for my $circ (@$circs) {
        if ($circ->target_copy->call_number->id == -1) {
            push(@circs, {
                circ => $circ,
                marc_xml => undef # pre-cat copy, use the dummy title/author instead
            });
            next;
        }
        my $bre_id = $circ->target_copy->call_number->record->id;
        my $unapi;
        if (exists $unapi_cache{$bre_id}) {
            $unapi = $unapi_cache{$bre_id};
        } else {
            my $result = $e->json_query({
                from => [
                    'unapi.bre', $bre_id, 'marcxml','record','{mra}', undef, undef, undef
                ]
            });
            if ($result) {
                $unapi_cache{$bre_id} = $unapi = XML::LibXML->new->parse_string($result->[0]->{'unapi.bre'});
            }
        }
        if ($unapi) {
            push(@circs, {
                circ => $circ,
                marc_xml => $unapi
            });
        } else {
            push(@circs, {
                circ => $circ,
                marc_xml => undef # failed, but try to go on
            });
        }
    }
    $e->rollback;

    return \@circs;
}

sub handle_circ_update {
    my $self     = shift;
    my $action   = shift;
    my $circ_ids = shift;

    $circ_ids //= [$self->cgi->param('circ_id')];

    if ($action =~ /delete/) {
        my $options = {
            circ_ids => $circ_ids,
        };

        $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.history.circ.clear',
            $self->editor->authtoken,
            $options
        );
    }

    return;
}

# TODO: action.usr_visible_holds does not return cancelled holds.  Should it?
sub load_myopac_hold_history {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $limit = $self->cgi->param('limit') || 15;
    my $offset = $self->cgi->param('offset') || 0;
    $ctx->{hold_history_limit} = $limit;
    $ctx->{hold_history_offset} = $offset;

    my $hold_ids = $e->json_query({
        select => {
            au => [{
                column => 'id',
                transform => 'action.usr_visible_holds',
                result_field => 'id'
            }]
        },
        from => 'au',
        where => {id => $e->requestor->id}
    });

    my $holds_object = $self->fetch_user_holds([map { $_->{id} } @$hold_ids], 0, 1, 0, $limit, $offset);
    if($holds_object->{holds}) {
        $ctx->{holds} = $holds_object->{holds};
    }
    $ctx->{hold_history_ids} = $holds_object->{all_ids};

    return Apache2::Const::OK;
}

sub load_myopac_payment_form {
    my $self = shift;
    my $r;
    my $e = $self->editor;

    $r = $self->prepare_fines(undef, undef, [$self->cgi->param('xact'), $self->cgi->param('xact_misc')]);

    if ( ! $self->cgi->param('last_chance')) { # only do this once
        if ($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.default') eq 'Stripe') {
            if ($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.stripe.enabled')) {
                my $skey = $self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.stripe.secretkey');
                my $currency = $self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.stripe.currency');
                my $amount = $self->ctx->{fines}->{balance_owed} * 100;

                # generate an idempotency key from the list of transactions to prevent duplicates;
                # if the list is empty, use (userID, YYYY-mm-dd, amount)
                my @payment_xacts = ($self->cgi->param('xact'), $self->cgi->param('xact_misc'));
                my $idempotency_key = md5_hex(scalar(@payment_xacts)
                    ? join(',', sort(@payment_xacts))
                    : join(',', $self->ctx->{user}->id, DateTime->now->strftime('%F'), $amount));
                my $default_headers = HTTP::Headers->new('Idempotency-Key' => $idempotency_key);
                my $stripe = Business::Stripe->new(-api_key => $skey, -ua_args => { default_headers => $default_headers } );

                my $intent = $stripe->api('post', 'payment_intents',
                    amount                => $amount,
                    currency              => $currency || 'usd',
                    description           => 'User Database ID: ' . $self->ctx->{user}->id
                );
                if ($stripe->success) {
                    $self->ctx->{stripe_client_secret} = $stripe->success()->{client_secret};
                } else {
                    $logger->error('Error initializing Stripe: ' . Dumper($stripe->error));
                    $self->ctx->{cc_configuration_error} = 1;
                }
            }
        } elsif ($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.default') eq 'SmartPAY') {
            if ($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.smartpay.enabled')) {
                my $location_id =  CGI::escapeHTML($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.smartpay.location_id'));
                $self->ctx->{smartpay_locationid} = $location_id;
                my $customer_id =  CGI::escapeHTML($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.smartpay.customer_id'));
                $self->ctx->{smartpay_customerid} = $customer_id;
                my $login = CGI::escapeHTML($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.smartpay.login'));
                my $password = CGI::escapeHTML($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.smartpay.password'));
                my $api_key = CGI::escapeHTML($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.smartpay.api_key'));
                my $server = CGI::escapeHTML($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.smartpay.server'));
                my $port = CGI::escapeHTML($self->ctx->{get_org_setting}->($e->requestor->home_ou, 'credit.processor.smartpay.port'));
                my $base_target = "https://$server";
                $base_target .= ":$port" if $port;
                $base_target .= "/SMARTPAYAPI/WEBSMARTPAY.dll";
                
                # first api call
                my $target = $base_target . "?RequestSessionKey";
                $target .= "&CustomerID=$customer_id";
                $target .= "&LocationID=$location_id";
                $target .= "&UserName=$login";
                $target .= "&Password=$password";
                $target .= "&APIKey=$api_key";

                my @payment_xacts = ($self->cgi->param('xact'), $self->cgi->param('xact_misc'));

                # generate a temporary cache token for our secret
                my $token = 'smartpay_' . md5_hex($$ . time() . rand());
                $target .= "&Secret=$token";

                my $ua = new LWP::UserAgent;

                # there has been API flux with whether to send API-Key and Secret as HTTP headers or URL params
                #my $req = GET($target, 'API-Key' => "$api_key", 'Secret' => "$token");
                my $req = GET($target);
                my $response = $ua->request($req);

                if ($response->is_success() && $response->content() !~ /HTML/) {
                    $logger->info('SmartPAY initialized for ' . $self->editor->authtoken . ' with ' . $token);

                    my $session_key = $response->content();

                    # we'll test this secret key again in the create payment method and grab the payment_xacts in main_pay_init
                    my $cache_args = {
                        user => $self->ctx->{user}->id,
                        session_key => $session_key,
                        xacts => \@payment_xacts
                    };
                    my $cache = OpenSRF::Utils::Cache->new('global');
                    $cache->put_cache($token, $cache_args, 3600); # 1 hour

                    # this will be for our follow-up call client-side

                    $self->ctx->{smartpay_target} = $base_target . '?GetCreditForm';
                    $self->ctx->{smartpay_target} .= '&SessionKey=' . $session_key;
                    $self->ctx->{smartpay_target} .= "&CustomerID=$customer_id";
                    $self->ctx->{smartpay_target} .= "&LocationID=$location_id";
                    $self->ctx->{smartpay_target} .= '&PatronID=' . $self->ctx->{user}->id; # $e->requestor->id;
                    my $psuedo_invoice_number = $self->cgi->param('xact') . ',' . $self->cgi->param('xact_misc');
                    $psuedo_invoice_number =~ s/^,//;
                    $self->ctx->{smartpay_target} .= "&InvNum=$psuedo_invoice_number";
                    $self->ctx->{smartpay_target} .= '&Amount=' . sprintf("%.2f",$self->ctx->{fines}->{balance_owed});
                    $self->ctx->{smartpay_target} .= '&URLPostBack=' . CGI::escapeHTML( $self->ctx->{hostname} );
                    #$self->ctx->{smartpay_target} .= '&ScriptPostBack=' .  CGI::escapeHTML('/cgi-bin/offline/echo1.pl');
                    $self->ctx->{smartpay_target} .= '&URLReturn=' .  CGI::escapeHTML( $self->ctx->{opac_root} . '/myopac/main_pay_init' );
                    $self->ctx->{smartpay_target} .= '&URLCancel=' .  CGI::escapeHTML( 'https://' . $self->ctx->{hostname} . $self->ctx->{opac_root} . '/myopac/main');
                    $self->ctx->{smartpay_target} .= '&UserName=&Password=&Field1=smartpay&Field2=&Field3=&ItemsData=';

                } else {
                    my $error = $response->content();
                    $error =~ s/[\r\n]//g;
                    $logger->error("Error initializing SmartPAY: $error");
                    $self->ctx->{cc_configuration_error} = 1;
                }
            }
        }
    }

    if ($r) { return $r; }
    $r = $self->prepare_extended_user_info and return $r;

    return Apache2::Const::OK;
}

# TODO: add other filter options as params/configs/etc.
sub load_myopac_payments {
    my $self = shift;
    my $limit = $self->cgi->param('limit') || 20;
    my $offset = $self->cgi->param('offset') || 0;
    my $e = $self->editor;

    $self->ctx->{payment_history_limit} = $limit;
    $self->ctx->{payment_history_offset} = $offset;

    my $args = {};
    $args->{limit} = $limit if $limit;
    $args->{offset} = $offset if $offset;

    if (my $max_age = $self->ctx->{get_org_setting}->(
        $e->requestor->home_ou, "opac.payment_history_age_limit"
    )) {
        my $min_ts = DateTime->now(
            "time_zone" => DateTime::TimeZone->new("name" => "local"),
        )->subtract("seconds" => interval_to_seconds($max_age))->iso8601();

        $logger->info("XXX min_ts: $min_ts");
        $args->{"where"} = {"payment_ts" => {">=" => $min_ts}};
    }

    $self->ctx->{payments} = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.payments.retrieve.atomic',
        $e->authtoken, $e->requestor->id, $args);

    return Apache2::Const::OK;
}

# 1. caches the form parameters
# 2. loads the credit card payment "Processing..." page
sub load_myopac_pay_init {
    my $self = shift;
    my $cache = OpenSRF::Utils::Cache->new('global');

    my @payment_xacts = ($self->cgi->param('xact'), $self->cgi->param('xact_misc'));

    if (!@payment_xacts) {
        if ($self->cgi->param('Secret')) { # we stashed the xacts in the cache for SmartPAY
            my $smartpay_cache = $cache->get_cache($self->cgi->param('Secret'));
            @payment_xacts = @{$smartpay_cache->{xacts}};
        } else {
            # for consistency with load_myopac_payment_form() and
            # to preserve backwards compatibility, if no xacts are
            # selected, assume all (applicable) transactions are wanted.
            my $stat = $self->prepare_fines(undef, undef, [$self->cgi->param('xact'), $self->cgi->param('xact_misc')]);
            return $stat if $stat;
            @payment_xacts =
                map { $_->{xact}->id } (
                    @{$self->ctx->{fines}->{circulation}},
                    @{$self->ctx->{fines}->{grocery}}
            );
        }
    }

    return $self->generic_redirect unless @payment_xacts;

    my $cc_args = {"where_process" => 1};

    $cc_args->{$_} = $self->cgi->param($_) for (qw/
        number cvv2 expire_year expire_month billing_first
        billing_last billing_address billing_city billing_state
        billing_zip stripe_payment_intent stripe_client_secret
    /);

    # mapping SmartPAY CGI parameters
    if ($self->cgi->param('Result')) {
        $cc_args->{smartpay_result} = $self->cgi->param('Result');
    }
    if ($self->cgi->param('Secret')) {
        $cc_args->{smartpay_secret} = $self->cgi->param('Secret');
    }
    if ($self->cgi->param('SessionKey')) {
        $cc_args->{smartpay_session} = $self->cgi->param('SessionKey');
    }
    if ($self->cgi->param('CCNumber')) {
        $cc_args->{number} = $self->cgi->param('CCNumber');
    }

    my $cache_args = {
        cc_args => $cc_args,
        user => $self->ctx->{user}->id,
        xacts => \@payment_xacts
    };

    # generate a temporary cache token and cache the form data
    my $token = md5_hex($$ . time() . rand());
    $cache->put_cache($token, $cache_args, 30);

    $logger->info("tpac caching payment info with token $token and xacts [@payment_xacts]");

    # after we render the processing page, we quickly redirect to submit
    # the actual payment.  The refresh url contains the payment token.
    # It also contains the list of xact IDs, which allows us to clear the
    # cache at the earliest possible time while leaving a trace of which
    # transactions we were processing, so the UI can bring the user back
    # to the payment form w/ the same xacts if the payment fails.

    my $refresh = "1; url=main_pay/$token?xact=" . pop(@payment_xacts);
    $refresh .= ";xact=$_" for @payment_xacts;
    $self->ctx->{refresh} = $refresh;

    return Apache2::Const::OK;
}

# retrieve the cached CC payment info and send off for processing
sub load_myopac_pay {
    my $self = shift;
    my $token = $self->ctx->{page_args}->[0];
    return Apache2::Const::HTTP_BAD_REQUEST unless $token;

    my $cache = OpenSRF::Utils::Cache->new('global');
    my $cache_args = $cache->get_cache($token);
    $cache->delete_cache($token);

    # this page is loaded immediately after the token is created.
    # if the cached data is not there, it's because of an invalid
    # token (or cache failure) and not because of a timeout.
    return Apache2::Const::HTTP_BAD_REQUEST unless $cache_args;

    my @payment_xacts = @{$cache_args->{xacts}};
    my $cc_args = $cache_args->{cc_args};

    # as an added security check, verify the user submitting
    # the form is the same as the user whose data was cached
    return Apache2::Const::HTTP_BAD_REQUEST unless
        $cache_args->{user} == $self->ctx->{user}->id;

    $logger->info("tpac paying fines with token $token and xacts [@payment_xacts]");

    my $r;
    $r = $self->prepare_fines(undef, undef, \@payment_xacts) and return $r;

    # balance_owed is computed specifically from the fines we're paying
    if ($self->ctx->{fines}->{balance_owed} <= 0) {
        $logger->info("tpac can't pay non-positive balance. xacts selected: [@payment_xacts]");
        return Apache2::Const::HTTP_BAD_REQUEST;
    }

    my $args = {
        "cc_args" => $cc_args,
        "userid" => $self->ctx->{user}->id,
        "payment_type" => "credit_card_payment",
        "payments" => $self->prepare_fines_for_payment  # should be safe after self->prepare_fines
    };

    my $resp = $U->simplereq("open-ils.circ", "open-ils.circ.money.payment",
        $self->editor->authtoken, $args, $self->ctx->{user}->last_xact_id
    );

    $self->ctx->{"payment_response"} = $resp;

    unless ($resp->{"textcode"}) {
        $self->ctx->{printable_receipt} = $U->simplereq(
        "open-ils.circ", "open-ils.circ.money.payment_receipt.print",
        $self->editor->authtoken, $resp->{payments}
        );
    }

    return Apache2::Const::OK;
}

sub load_myopac_receipt_print {
    my $self = shift;

    $self->ctx->{printable_receipt} = $U->simplereq(
    "open-ils.circ", "open-ils.circ.money.payment_receipt.print",
    $self->editor->authtoken, [$self->cgi->param("payment")]
    );

    return Apache2::Const::OK;
}

sub load_myopac_receipt_email {
    my $self = shift;

    # The following ML method doesn't actually check whether the user in
    # question has an email address, so we do.
    if ($self->ctx->{user}->email) {
        $self->ctx->{email_receipt_result} = $U->simplereq(
        "open-ils.circ", "open-ils.circ.money.payment_receipt.email",
        $self->editor->authtoken, [$self->cgi->param("payment")]
        );
    } else {
        $self->ctx->{email_receipt_result} =
            new OpenILS::Event("PATRON_NO_EMAIL_ADDRESS");
    }

    return Apache2::Const::OK;
}

sub prepare_fines {
    my ($self, $limit, $offset, $id_list) = @_;

    # XXX TODO: check for failure after various network calls

    # It may be unclear, but this result structure lumps circulation and
    # reservation fines together, and keeps grocery fines separate.
    $self->ctx->{"fines"} = {
        "circulation" => [],
        "grocery" => [],
        "total_paid" => 0,
        "total_owed" => 0,
        "balance_owed" => 0
    };

    my $cstore = OpenSRF::AppSession->create('open-ils.cstore');

    # TODO: This should really be a ML call, but the existing calls
    # return an excessive amount of data and don't offer streaming

    my %paging = ($limit or $offset) ? (limit => $limit, offset => $offset) : ();

    my $req = $cstore->request(
        'open-ils.cstore.direct.money.open_billable_transaction_summary.search',
        {
            usr => $self->editor->requestor->id,
            balance_owed => {'!=' => 0},
            ($id_list && @$id_list ? ("id" => $id_list) : ()),
        },
        {
            flesh => 4,
            flesh_fields => {
                mobts => [qw/grocery circulation reservation/],
                bresv => ['target_resource_type'],
                brt => ['record'],
                mg => ['billings'],
                mb => ['btype'],
                circ => ['target_copy'],
                acp => ['call_number'],
                acn => ['record']
            },
            order_by => { mobts => 'xact_start' },
            %paging
        }
    );

    # Collect $$ amounts from each transaction for summing below.
    my (@paid_amounts, @owed_amounts, @balance_amounts);

    while(my $resp = $req->recv) {
        my $mobts = $resp->content;
        my $circ = $mobts->circulation;

        my $last_billing;
        if($mobts->grocery) {
            my @billings = sort { $a->billing_ts cmp $b->billing_ts } @{$mobts->grocery->billings};
            $last_billing = pop(@billings);
        }

        push(@paid_amounts, $mobts->total_paid);
        push(@owed_amounts, $mobts->total_owed);
        push(@balance_amounts, $mobts->balance_owed);

        my $marc_xml = undef;
        if ($mobts->xact_type eq 'reservation' and
            $mobts->reservation->target_resource_type->record) {
            $marc_xml = XML::LibXML->new->parse_string(
                $mobts->reservation->target_resource_type->record->marc
            );
        } elsif ($mobts->xact_type eq 'circulation' and
            $circ->target_copy->call_number->id != -1) {
            $marc_xml = XML::LibXML->new->parse_string(
                $circ->target_copy->call_number->record->marc
            );
        }

        push(
            @{$self->ctx->{"fines"}->{$mobts->grocery ? "grocery" : "circulation"}},
            {
                xact => $mobts,
                last_grocery_billing => $last_billing,
                marc_xml => $marc_xml
            }
        );
    }

    $cstore->kill_me;

    $self->ctx->{"fines"}->{total_paid}   = $U->fpsum(@paid_amounts);
    $self->ctx->{"fines"}->{total_owed}   = $U->fpsum(@owed_amounts);
    $self->ctx->{"fines"}->{balance_owed} = $U->fpsum(@balance_amounts);

    return;
}

sub prepare_fines_for_payment {
    # This assumes $self->prepare_fines has already been run
    my ($self) = @_;

    my @results = ();
    if ($self->ctx->{fines}) {
        push @results, [$_->{xact}->id, $_->{xact}->balance_owed] foreach (
            @{$self->ctx->{fines}->{circulation}},
            @{$self->ctx->{fines}->{grocery}}
        );
    }

    return \@results;
}

sub load_myopac_main {
    my $self = shift;
    my $limit = $self->cgi->param('limit') || 0;
    my $offset = $self->cgi->param('offset') || 0;
    $self->ctx->{search_ou} = $self->_get_search_lib();
    $self->ctx->{user}->notes(
        $self->editor->search_actor_usr_message({
            usr => $self->ctx->{user}->id,
            pub => 't'
        })
    );

    # PINES - need to make sure we're retrieving current info
# NEEDS WORK - NOT SURE WHY THIS LINE IS BREAKING ACCOUNTS THAT HAVE CHARGES
#    $self->prepare_extended_user_info;

    # Check whether or not to provide account renewal link, fetching
    # patron record from database to be sure that we have the most recent
    # data
    my $user = $self->editor->retrieve_actor_user([$self->ctx->{user}->id,
        {
            flesh => 1,
            flesh_fields => {
                au => ['billing_address', 'mailing_address']
            }
        }
    ]);
    if ($user->billing_address and $user->billing_address->valid and $user->billing_address->valid eq 't') {
        $self->ctx->{valid_billing_address} = 1;
    } else {
        $self->ctx->{valid_billing_address} = 0;
    }
    if ($user->mailing_address and $user->mailing_address->valid and $user->mailing_address->valid eq 't') {
        $self->ctx->{valid_mailing_address} = 1;
    } else {
        $self->ctx->{valid_mailing_address} = 0;
    }
    $self->check_account_exp();

    return $self->prepare_fines($limit, $offset) || Apache2::Const::OK;
}

sub load_myopac_update_email {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $email = $self->cgi->param('email') || '';
    my $current_pw = $self->cgi->param('current_pw') || '';

    # needed for most up-to-date email address
    if (my $r = $self->prepare_extended_user_info) { return $r };

    return Apache2::Const::OK
        unless $self->cgi->request_method eq 'POST';

    unless($email =~ /.+\@.+\..+/) { # TODO better regex?
        $ctx->{invalid_email} = $email;
        return Apache2::Const::OK;
    }

    my $stat = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.email.update',
        $e->authtoken, $email, $current_pw);

    if($U->event_equals($stat, 'INCORRECT_PASSWORD')) {
        $ctx->{password_incorrect} = 1;
        return Apache2::Const::OK;
    }

    unless ($self->cgi->param("redirect_to")) {
        my $url = $self->apache->unparsed_uri;
        $url =~ s/update_email/prefs/;

        return $self->generic_redirect($url);
    }

    return $self->generic_redirect;
}

sub load_myopac_update_username {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $username = $self->cgi->param('username') || '';
    my $current_pw = $self->cgi->param('current_pw') || '';

    $self->prepare_extended_user_info;

    my $allow_change = 1;
    my $regex_check;
    my $lock_usernames = $self->ctx->{get_org_setting}->($e->requestor->home_ou, 'opac.lock_usernames');
    if(defined($lock_usernames) and $lock_usernames == 1) {
        # Policy says no username changes
        $allow_change = 0;
    } else {
        # We want this further down.
        $regex_check = $self->ctx->{get_org_setting}->($e->requestor->home_ou, 'opac.barcode_regex');
        my $username_unlimit = $self->ctx->{get_org_setting}->($e->requestor->home_ou, 'opac.unlimit_usernames');
        if(!$username_unlimit) {
            if(!$regex_check) {
                # Default is "starts with a number"
                $regex_check = '^\d+';
            }
            # You already have a username?
            if($regex_check and $self->ctx->{user}->usrname !~ /$regex_check/) {
                $allow_change = 0;
            }
        }
    }
    if(!$allow_change) {
        my $url = $self->apache->unparsed_uri;
        $url =~ s/update_username/prefs/;

        return $self->generic_redirect($url);
    }

    return Apache2::Const::OK
        unless $self->cgi->request_method eq 'POST';

    unless($username and $username !~ /\s/) { # any other username restrictions?
        $ctx->{invalid_username} = $username;
        return Apache2::Const::OK;
    }

    # New username can't look like a barcode if we have a barcode regex
    if($regex_check and $username =~ /$regex_check/) {
        $ctx->{invalid_username} = $username;
        return Apache2::Const::OK;
    }

    # New username has to look like a username if we have a username regex
    $regex_check = $ctx->{get_org_setting}->($e->requestor->home_ou, 'opac.username_regex');
    if($regex_check and $username !~ /$regex_check/) {
        $ctx->{invalid_username} = $username;
        return Apache2::Const::OK;
    }

    if($username ne $e->requestor->usrname) {

        my $evt = $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.user.username.update',
            $e->authtoken, $username, $current_pw);

        if($U->event_equals($evt, 'INCORRECT_PASSWORD')) {
            $ctx->{password_incorrect} = 1;
            return Apache2::Const::OK;
        }

        if($U->event_equals($evt, 'USERNAME_EXISTS')) {
            $ctx->{username_exists} = $username;
            return Apache2::Const::OK;
        }
    }

    my $url = $self->apache->unparsed_uri;
    $url =~ s/update_username/prefs/;

    return $self->generic_redirect($url);
}

sub load_myopac_update_locale {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $lang = $self->cgi->param('pref_lang') || '';
    my $current_pw = $self->cgi->param('current_pw') || '';

    $self->prepare_extended_user_info;

    my $locs = $U->simplereq(
        'open-ils.cstore',
        "open-ils.cstore.direct.config.i18n_locale.search.atomic", 
	{ "code" => { "!=" => undef } }
    );

    my %user_locales;
    foreach my $l (@$locs) { $user_locales{$l->code} = $l->name; }
    $self->ctx->{i18n_locales} = \%user_locales; 

    return Apache2::Const::OK
        unless $self->cgi->request_method eq 'POST';

    if($lang ne $e->requestor->locale) {
        my $evt = $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.user.locale.update',
            $e->authtoken, $lang, $current_pw);

        if($U->event_equals($evt, 'INCORRECT_PASSWORD')) {
            $ctx->{password_incorrect} = 1;
            return Apache2::Const::OK;
        }
    }

    my $url = $self->apache->unparsed_uri;
    $url =~ s/update_locale/prefs/;

    return $self->generic_redirect($url);
}

sub load_myopac_update_password {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    return Apache2::Const::OK
        unless $self->cgi->request_method eq 'POST';

    my $current_pw = $self->cgi->param('current_pw') || '';
    my $new_pw = $self->cgi->param('new_pw') || '';
    my $new_pw2 = $self->cgi->param('new_pw2') || '';

    unless($new_pw eq $new_pw2) {
        $ctx->{password_nomatch} = 1;
        return Apache2::Const::OK;
    }

    my $pw_regex = $ctx->{get_org_setting}->($e->requestor->home_ou, 'global.password_regex');

    if(!$pw_regex) {
        # This regex duplicates the JSPac's default "digit, letter, and 7 characters" rule
        $pw_regex = '(?=.*\d+.*)(?=.*[A-Za-z]+.*).{7,}';
    }

    if($pw_regex and $new_pw !~ /$pw_regex/) {
        $ctx->{password_invalid} = 1;
        return Apache2::Const::OK;
    }

    my $evt = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.password.update',
        $e->authtoken, $new_pw, $current_pw);


    if($U->event_equals($evt, 'INCORRECT_PASSWORD')) {
        $ctx->{password_incorrect} = 1;
        return Apache2::Const::OK;
    }

    my $url = $self->apache->unparsed_uri;
    $url =~ s/update_password/prefs/;

    return $self->generic_redirect($url);
}

sub load_myopac_update_preferred_name {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    $self->prepare_extended_user_info;

    return Apache2::Const::OK
        unless $self->cgi->request_method eq 'POST';

    my $current_pw = $self->cgi->param('current_pw') || '';

    my %opac_vals = ();

    foreach(qw/ pref_prefix pref_first_given_name pref_second_given_name pref_family_name pref_suffix/ ){
        $opac_vals{$_} = $self->cgi->param($_) if($self->cgi->param($_) && $self->cgi->param($_) ne '');
    }

    my $evt = $U->simplereq('open-ils.actor', 'open-ils.actor.user.preferred_name.update',
        $e->authtoken, \%opac_vals, $current_pw);

    if($U->event_equals($evt, 'INCORRECT_PASSWORD')) {
        $ctx->{password_incorrect} = 1;
        return Apache2::Const::OK;
    }

    if($U->event_equals($evt, 'BAD_PARAM')) {
        $ctx->{bad_param} = 1;
        return Apache2::Const::OK;
    }

    foreach(qw/ pref_prefix pref_first_given_name pref_second_given_name pref_family_name pref_suffix/ ){
        $self->ctx->{user}->$_($opac_vals{$_});
    }

    my $url = $self->apache->unparsed_uri;
    $url =~ s/update_preferred_name/prefs/;

    return $self->generic_redirect($url);

}

sub _update_bookbag_metadata {
    my ($self, $bookbag) = @_;

    $bookbag->name($self->cgi->param("name"));
    $bookbag->description($self->cgi->param("description"));

    return 1 if $self->editor->update_container_biblio_record_entry_bucket($bookbag);
    return 0;
}

sub _get_lists_per_page {
    my $self = shift;

    if($self->editor->requestor) {
        $self->timelog("Checking for opac.lists_per_page preference");
        # See if the user has a lists per page preference
        my $ipp = $self->editor->search_actor_user_setting({
            usr => $self->editor->requestor->id,
            name => 'opac.lists_per_page'
        })->[0];
        $self->timelog("Got opac.lists_per_page preference");
        return OpenSRF::Utils::JSON->JSON2perl($ipp->value) if $ipp;
    }
    return 10; # default
}

sub _get_items_per_page {
    my $self = shift;

    if($self->editor->requestor) {
        $self->timelog("Checking for opac.list_items_per_page preference");
        # See if the user has a list items per page preference
        my $ipp = $self->editor->search_actor_user_setting({
            usr => $self->editor->requestor->id,
            name => 'opac.list_items_per_page'
        })->[0];
        $self->timelog("Got opac.list_items_per_page preference");
        return OpenSRF::Utils::JSON->JSON2perl($ipp->value) if $ipp;
    }
    return 10; # default
}

sub load_myopac_bookbags {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $limit = $self->_get_lists_per_page || 10;
    my $offset = $self->cgi->param('offset') || 0;

    $ctx->{bookbags_limit} = $limit;
    $ctx->{bookbags_offset} = $offset;

    # for list item pagination
    my $item_limit = $self->_get_items_per_page;
    my $item_page = $self->cgi->param('item_page') || 1;
    my $item_offset = ($item_page - 1) * $item_limit;
    $ctx->{bookbags_item_page} = $item_page;

    my ($sorter, $modifier) = $self->_get_bookbag_sort_params("sort");
    $e->xact_begin; # replication...

    my $rv = $self->load_mylist;
    unless($rv eq Apache2::Const::OK) {
        $e->rollback;
        return $rv;
    }

    $ctx->{bookbags} = $e->search_container_biblio_record_entry_bucket(
        [
            {owner => $e->requestor->id, btype => 'bookbag'}, {
                order_by => {cbreb => 'name'},
                limit => $limit,
                offset => $offset
            }
        ],
        {substream => 1}
    );

    if(!$ctx->{bookbags}) {
        $e->rollback;
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    # We load the user prefs to get their default bookbag.
    $self->_load_user_with_prefs;

    # We also want a total count of the user's bookbags.
    my $q = {
        'select' => { 'cbreb' => [ { 'column' => 'id', 'transform' => 'count', 'aggregate' => 'true', 'alias' => 'count' } ] },
        'from' => 'cbreb',
        'where' => { 'btype' => 'bookbag', 'owner' => $self->ctx->{user}->id }
    };
    my $r = $e->json_query($q);
    $ctx->{bookbag_count} = $r->[0]->{'count'};

    # If the user wants a specific bookbag's items, load them.

    if ($self->cgi->param("bbid")) {
        my ($bookbag) =
            grep { $_->id eq $self->cgi->param("bbid") } @{$ctx->{bookbags}};

        if ($bookbag) {
            my $query = $self->_prepare_bookbag_container_query(
                $bookbag->id, $sorter, $modifier
            );

            # Calculate total count of the items in selected bookbag.
            # This total includes record entries that have no assets available.
            my $bb_search_results = $U->simplereq(
                "open-ils.search", "open-ils.search.biblio.multiclass.query",
                {"limit" => 1, "offset" => 0}, $query
            ); # we only need the count, so do the actual search with limit=1

            if ($bb_search_results) {
                $ctx->{bb_item_count} = $bb_search_results->{count};
            } else {
                $logger->warn("search failed in load_myopac_bookbags()");
                $ctx->{bb_item_count} = 0; # fallback value
            }

            #calculate page count
            $ctx->{bb_page_count} = int ((($ctx->{bb_item_count} - 1) / $item_limit) + 1);

            if ( ($self->cgi->param("action") || '') eq "editmeta") {
                if (!$self->_update_bookbag_metadata($bookbag))  {
                    $e->rollback;
                    return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
                } else {
                    $e->commit;
                    my $url = $self->ctx->{opac_root} . '/myopac/lists?bbid=' .
                        $bookbag->id;

                    foreach my $param (('loc', 'qtype', 'query', 'sort', 'offset', 'limit')) {
                        if ($self->cgi->param($param)) {
                            my @vals = $self->cgi->param($param);
                            $url .= ";$param=" . uri_escape_utf8($_) foreach @vals;
                        }
                    }

                    return $self->generic_redirect($url);
                }
            }

            # we're done with our CStoreEditor.  Rollback here so
            # later calls don't cause a timeout, resulting in a
            # transaction rollback under the covers.
            $e->rollback;


            # For list items pagination
            my $args = {
                "limit" => $item_limit,
                "offset" => $item_offset
            };

            my $items = $U->bib_container_items_via_search($bookbag->id, $query, $args)
                or return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;

            # capture pref_ou for callnumber filter/display
            $ctx->{pref_ou} = $self->_get_pref_lib() || $ctx->{search_ou};

            # search for local callnumbers for display
            my $focus_ou = $ctx->{physical_loc} || $ctx->{pref_ou};

            my (undef, @recs) = $self->get_records_and_facets(
                [ map {$_->target_biblio_record_entry->id} @$items ],
                undef,
                {
                    flesh => '{mra,holdings_xml,acp,exclude_invisible_acn}',
                    flesh_depth => 1,
                    site => $ctx->{get_aou}->($focus_ou)->shortname,
                    pref_lib => $ctx->{pref_ou}
                }
            );

            $ctx->{bookbags_marc_xml}{$_->{id}} = $_->{marc_xml} for @recs;

            $bookbag->items($items);
        }
    }

    # If we have add_rec, we got here from the "Add to new list"
    # or "See all" popmenu items.
    if (my $add_rec = $self->cgi->param('add_rec')) {
        $self->ctx->{add_rec} = $add_rec;
        # But not in the staff client, 'cause that breaks things.
        unless ($self->ctx->{is_staff}) {
            # allow caller to provide the where_from in cases where
            # the referer is an intermediate error page
            if ($self->cgi->param('where_from')) {
                $self->ctx->{where_from} = $self->cgi->param('where_from');
            } else {
                $self->ctx->{where_from} = $self->ctx->{referer};
                if ( my $anchor = $self->cgi->param('anchor') ) {
                    $self->ctx->{where_from} =~ s/#.*|$/#$anchor/;
                }
            }
        }
    }

    # this rollback may be a dupe, but that's OK because
    # cstoreditor ignores dupe rollbacks
    $e->rollback;

    return Apache2::Const::OK;
}


# actions are create, delete, show, hide, rename, add_rec, delete_item, place_hold, print, email
# CGI is action, list=list_id, add_rec/record=bre_id, del_item=bucket_item_id, name=new_bucket_name
sub load_myopac_bookbag_update {
    my ($self, $action, $list_id, @hold_recs) = @_;
    my $e = $self->editor;
    my $cgi = $self->cgi;

    # save_notes is effectively another action, but is passed in a separate
    # CGI parameter for what are really just layout reasons.
    $action = 'save_notes' if $cgi->param('save_notes');
    $action ||= $cgi->param('action');

    $list_id ||= $cgi->param('list') || $cgi->param('bbid');

    my @add_rec = $cgi->param('add_rec') || $cgi->param('record');
    my @selected_item = $cgi->param('selected_item');
    my $shared = $cgi->param('shared');
    my $move_cart = $cgi->param('move_cart');
    my $name = $cgi->param('name');
    my $description = $cgi->param('description');
    my $success = 0;
    my $list;

    # bail out if user is attempting an action that requires
    # that at least one list item be selected
    if ((scalar(@selected_item) == 0) && (scalar(@hold_recs) == 0) &&
        ($action eq 'place_hold' || $action eq 'print' ||
         $action eq 'email' || $action eq 'del_item')) {
        my $url = $self->ctx->{referer};
        $url .= ($url =~ /\?/ ? '&' : '?') . 'list_none_selected=1' unless $url =~ /list_none_selected/;
        return $self->generic_redirect($url);
    }

    # This url intentionally leaves off the edit_notes parameter, but
    # may need to add some back in for paging.

    my $url = $self->ctx->{proto} . "://" . $self->ctx->{hostname} .
        $self->ctx->{opac_root} . "/myopac/lists?";

    foreach my $param (('loc', 'qtype', 'query', 'sort')) {
        if ($cgi->param($param)) {
            my @vals = $cgi->param($param);
            $url .= ";$param=" . uri_escape_utf8($_) foreach @vals;
        }
    }

    if ($action eq 'create') {

        if ($name) {
            $list = Fieldmapper::container::biblio_record_entry_bucket->new;
            $list->name($name);
            $list->description($description);
            $list->owner($e->requestor->id);
            $list->btype('bookbag');
            $list->pub($shared ? 't' : 'f');
            $success = $U->simplereq('open-ils.actor',
                'open-ils.actor.container.create', $e->authtoken, 'biblio', $list);
            if (ref($success) ne 'HASH') {
                $list_id = (ref($success)) ? $success->id : $success;
                if (scalar @add_rec) {
                    foreach my $add_rec (@add_rec) {
                        my $item = Fieldmapper::container::biblio_record_entry_bucket_item->new;
                        $item->bucket($list_id);
                        $item->target_biblio_record_entry($add_rec);
                        $success = $U->simplereq('open-ils.actor',
                                                'open-ils.actor.container.item.create', $e->authtoken, 'biblio', $item);
                        last unless $success;
                    }
                }
                if ($move_cart) {
                    my ($cache_key, $list) = $self->fetch_mylist(0, 1);
                    foreach my $add_rec (@$list) {
                        my $item = Fieldmapper::container::biblio_record_entry_bucket_item->new;
                        $item->bucket($list_id);
                        $item->target_biblio_record_entry($add_rec);
                        $success = $U->simplereq('open-ils.actor',
                                                'open-ils.actor.container.item.create', $e->authtoken, 'biblio', $item);
                        last unless $success;
                    }
                    $self->clear_anon_cache;
                }
            }
            $url = $cgi->param('where_from') if ($success && $cgi->param('where_from'));

        } else { # no name
            $self->ctx->{bucket_failure_noname} = 1;
        }

    } elsif($action eq 'place_hold') {

        # @hold_recs comes from anon lists redirect; selected_items comes from existing buckets
        my $from_basket = scalar(@hold_recs);
        unless (@hold_recs) {
            if (@selected_item) {
                my $items = $e->search_container_biblio_record_entry_bucket_item({id => \@selected_item});
                @hold_recs = map { $_->target_biblio_record_entry } @$items;
            }
        }

        return Apache2::Const::OK unless @hold_recs;
        $logger->info("placing holds from list page on: @hold_recs");

        my $url = $self->ctx->{opac_root} . '/place_hold?hold_type=T';
        $url .= ';hold_target=' . $_ for @hold_recs;
        $url .= ';from_basket=1' if $from_basket;
        $url .= ';clear_cart=1' if $cgi->param('clear_cart');
        foreach my $param (('loc', 'qtype', 'query')) {
            if ($cgi->param($param)) {
                my @vals = $cgi->param($param);
                $url .= ";$param=" . uri_escape_utf8($_) foreach @vals;
            }
        }
        return $self->generic_redirect($url);

    } elsif ($action eq 'print') {
        my ($incoming_sort,$sort_dir) = $self->_get_bookbag_sort_params('sort');
        $sort_dir = $self->cgi->param('sort_dir') if $self->cgi->param('sort_dir');
        if (!$incoming_sort) {
            ($incoming_sort,$sort_dir) = $self->_get_bookbag_sort_params('anonsort');
        }
        if (!$incoming_sort) {
            $incoming_sort = 'author';
        }

        $incoming_sort =~ s/sort.*$//;

        $self->ctx->{sort} = $incoming_sort;
        $self->ctx->{sort_dir} = $sort_dir;

        my $items = $self->editor->search_container_biblio_record_entry_bucket_item({id=>\@selected_item});
        my @bib_ids = map { $_->target_biblio_record_entry } @$items;
        my $temp_cache_key = $self->_stash_record_list_in_anon_cache(@bib_ids);
        return $self->load_mylist_print($temp_cache_key);
    } elsif ($action eq 'email') {
        my ($incoming_sort,$sort_dir) = $self->_get_bookbag_sort_params('sort');
        $sort_dir = $self->cgi->param('sort_dir') if $self->cgi->param('sort_dir');
        if (!$incoming_sort) {
            ($incoming_sort,$sort_dir) = $self->_get_bookbag_sort_params('anonsort');
        }
        if (!$incoming_sort) {
            $incoming_sort = 'author';
        }

        $incoming_sort =~ s/sort.*$//;

        $self->ctx->{sort} = $incoming_sort;
        $self->ctx->{sort_dir} = $sort_dir;

        my $items = $self->editor->search_container_biblio_record_entry_bucket_item({id=>\@selected_item});
        my @bib_ids = map { $_->target_biblio_record_entry } @$items;
        my $temp_cache_key = $self->_stash_record_list_in_anon_cache(@bib_ids);
        return $self->load_mylist_email($temp_cache_key);
    } else {

        $list = $e->retrieve_container_biblio_record_entry_bucket($list_id);

        return Apache2::Const::HTTP_BAD_REQUEST unless
            $list and $list->owner == $e->requestor->id;
    }

    if($action eq 'delete') {
        $success = $U->simplereq('open-ils.actor',
            'open-ils.actor.container.full_delete', $e->authtoken, 'biblio', $list_id);
        if ($success) {
            # We check to see if we're deleting the user's default list.
            $self->_load_user_with_prefs;
            my $settings_map = $self->ctx->{user_setting_map};
            if ($$settings_map{'opac.default_list'} == $list_id) {
                # We unset the user's opac.default_list setting.
                $success = $U->simplereq(
                    'open-ils.actor',
                    'open-ils.actor.patron.settings.update',
                    $e->authtoken,
                    $e->requestor->id,
                    { 'opac.default_list' => 0 }
                );
            }
        }
    } elsif($action eq 'show') {
        unless($U->is_true($list->pub)) {
            $list->pub('t');
            $success = $U->simplereq('open-ils.actor',
                'open-ils.actor.container.update', $e->authtoken, 'biblio', $list);
        }

    } elsif($action eq 'hide') {
        if($U->is_true($list->pub)) {
            $list->pub('f');
            $success = $U->simplereq('open-ils.actor',
                'open-ils.actor.container.update', $e->authtoken, 'biblio', $list);
        }

    } elsif($action eq 'rename') {
        if($name) {
            $list->name($name);
            $success = $U->simplereq('open-ils.actor',
                'open-ils.actor.container.update', $e->authtoken, 'biblio', $list);
        }

    } elsif($action eq 'add_rec') {
        foreach my $add_rec (@add_rec) {
            my $item = Fieldmapper::container::biblio_record_entry_bucket_item->new;
            $item->bucket($list_id);
            $item->target_biblio_record_entry($add_rec);
            $success = $U->simplereq('open-ils.actor',
                'open-ils.actor.container.item.create', $e->authtoken, 'biblio', $item);
            last unless $success;
        }
        # Redirect back where we came from if we have an anchor parameter:
        if ( my $anchor = $cgi->param('anchor') && !$self->ctx->{is_staff}) {
            $url = $self->ctx->{referer};
            $url =~ s/#.*|$/#$anchor/;
        } elsif ($cgi->param('where_from')) {
            # Or, if we have a "where_from" parameter.
            $url = $cgi->param('where_from');
        }
    } elsif ($action eq 'del_item') {
        foreach (@selected_item) {
            $success = $U->simplereq(
                'open-ils.actor',
                'open-ils.actor.container.item.delete', $e->authtoken, 'biblio', $_
            );
            last unless $success;
        }
    } elsif ($action eq 'save_notes') {
        $success = $self->update_bookbag_item_notes;
        $url .= "&bbid=" . uri_escape_utf8($cgi->param("bbid")) if $cgi->param("bbid");
    } elsif ($action eq 'make_default') {
        $success = $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.patron.settings.update',
            $e->authtoken,
            $list->owner,
            { 'opac.default_list' => $list_id }
        );
    } elsif ($action eq 'remove_default') {
        $success = $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.patron.settings.update',
            $e->authtoken,
            $list->owner,
            { 'opac.default_list' => 0 }
        );
    }

    return $self->generic_redirect($url) if $success;

    $self->ctx->{where_from} = $cgi->param('where_from');
    $self->ctx->{bucket_action} = $action;
    $self->ctx->{bucket_action_failed} = 1;
    return Apache2::Const::OK;
}

sub update_bookbag_item_notes {
    my ($self) = @_;
    my $e = $self->editor;

    my @note_keys = grep /^note-\d+/, keys(%{$self->cgi->Vars});
    my @item_keys = grep /^item-\d+/, keys(%{$self->cgi->Vars});

    # We're going to leverage an API call that's already been written to check
    # permissions appropriately.

    my $a = create OpenSRF::AppSession("open-ils.actor");
    my $method = "open-ils.actor.container.item_note.cud";

    for my $note_key (@note_keys) {
        my $note;

        my $id = ($note_key =~ /(\d+)/)[0];

        if (!($note =
            $e->retrieve_container_biblio_record_entry_bucket_item_note($id))) {
            my $event = $e->die_event;
            $self->apache->log->warn(
                "error retrieving cbrebin id $id, got event " .
                $event->{textcode}
            );
            $a->kill_me;
            $self->ctx->{bucket_action_event} = $event;
            return;
        }

        if (length($self->cgi->param($note_key))) {
            $note->ischanged(1);
            $note->note($self->cgi->param($note_key));
        } else {
            $note->isdeleted(1);
        }

        my $r = $a->request($method, $e->authtoken, "biblio", $note)->gather(1);

        if (defined $U->event_code($r)) {
            $self->apache->log->warn(
                "attempt to modify cbrebin " . $note->id .
                " returned event " .  $r->{textcode}
            );
            $e->rollback;
            $a->kill_me;
            $self->ctx->{bucket_action_event} = $r;
            return;
        }
    }

    for my $item_key (@item_keys) {
        my $id = int(($item_key =~ /(\d+)/)[0]);
        my $text = $self->cgi->param($item_key);

        chomp $text;
        next unless length $text;

        my $note = new Fieldmapper::container::biblio_record_entry_bucket_item_note;
        $note->isnew(1);
        $note->item($id);
        $note->note($text);

        my $r = $a->request($method, $e->authtoken, "biblio", $note)->gather(1);

        if (defined $U->event_code($r)) {
            $self->apache->log->warn(
                "attempt to create cbrebin for item " . $note->item .
                " returned event " .  $r->{textcode}
            );
            $e->rollback;
            $a->kill_me;
            $self->ctx->{bucket_action_event} = $r;
            return;
        }
    }

    $a->kill_me;
    return 1;   # success
}

sub load_myopac_bookbag_print {
    my ($self) = @_;

    my $id = int($self->cgi->param("list"));

    my ($sorter, $modifier) = $self->_get_bookbag_sort_params("sort");

    my $item_search =
        $self->_prepare_bookbag_container_query($id, $sorter, $modifier);

    my $bbag;

    # Get the bookbag object itself, assuming we're allowed to.
    if ($self->editor->allowed("VIEW_CONTAINER")) {

        $bbag = $self->editor->retrieve_container_biblio_record_entry_bucket($id) or return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    } else {
        my $bookbags = $self->editor->search_container_biblio_record_entry_bucket(
            {
                "id" => $id,
                "-or" => {
                    "owner" => $self->editor->requestor->id,
                    "pub" => "t"
                }
            }
        ) or return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;

        $bbag = pop @$bookbags;
    }

    # If we have a bookbag we're allowed to look at, issue the A/T event
    # to get CSV, passing as a user param that search query we built before.
    if ($bbag) {
        $self->ctx->{csv} = $U->fire_object_event(
            undef, "container.biblio_record_entry_bucket.csv",
            $bbag, $self->editor->requestor->home_ou,
            undef, {"item_search" => $item_search}
        );
    }

    # Create a reasonable filename and set the content disposition to
    # provoke browser download dialogs.
    (my $filename = $bbag->id . $bbag->name) =~ s/[^a-z0-9_ -]//gi;

    return $self->set_file_download_headers("$filename.csv");
}

sub load_myopac_circ_history_export {
    my $self = shift;
    my $e = $self->editor;
    my $filename = $self->cgi->param('filename') || 'circ_history.csv';

    my $circs = $self->fetch_user_circ_history(1);

    $self->ctx->{csv}->{circs} = $circs;
    return $self->set_file_download_headers($filename, 'text/csv; encoding=UTF-8');

}

sub load_myopac_reservations {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    my $upcoming = $U->simplereq("open-ils.booking", "open-ils.booking.reservations.upcoming_reservation_list_by_user",
        $e->authtoken, undef
    );

    $ctx->{reservations} = $upcoming;
    return Apache2::Const::OK;

}

sub load_password_reset {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;
    my $barcode = $cgi->param('barcode');
    my $username = $cgi->param('username');
    my $email = $cgi->param('email');
    my $pwd1 = $cgi->param('pwd1');
    my $pwd2 = $cgi->param('pwd2');
    my $uuid = $ctx->{page_args}->[0];

    if ($uuid) {

        $logger->info("patron password reset with uuid $uuid");

        if ($pwd1 and $pwd2) {

            if ($pwd1 eq $pwd2) {

                my $response = $U->simplereq(
                    'open-ils.actor',
                    'open-ils.actor.patron.password_reset.commit',
                    $uuid, $pwd1);

                $logger->info("patron password reset response " . Dumper($response));

                if ($U->event_code($response)) { # non-success event

                    my $code = $response->{textcode};

                    if ($code eq 'PATRON_NOT_AN_ACTIVE_PASSWORD_RESET_REQUEST') {
                        $ctx->{pwreset} = {style => 'error', status => 'NOT_ACTIVE'};
                    }

                    if ($code eq 'PATRON_PASSWORD_WAS_NOT_STRONG') {
                        $ctx->{pwreset} = {style => 'error', status => 'NOT_STRONG'};
                    }

                } else { # success

                    $ctx->{pwreset} = {style => 'success', status => 'SUCCESS'};
                }

            } else { # passwords not equal

                $ctx->{pwreset} = {style => 'error', status => 'NO_MATCH'};
            }

        } else { # 2 password values needed

            $ctx->{pwreset} = {status => 'TWO_PASSWORDS'};
        }

    } elsif ($barcode or $username) {

        my @params = $barcode ? ('barcode', $barcode) : ('username', $username);
        push(@params, $email) if $email;

        $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.patron.password_reset.request', @params);

        $ctx->{pwreset} = {status => 'REQUEST_SUCCESS'};
    }

    $logger->info("patron password reset resulted in " . Dumper($ctx->{pwreset}));
    return Apache2::Const::OK;
}

# PINES - check whether patron has standing penalties that should block
# online account renewal
sub has_penalties {
    my $self = shift;
    my $ctx = $self->ctx;
    my $user = $self->ctx->{user};
    my $e = new_editor(xact => 1);
    
    my $erenew_blocking_penalties = $e->search_actor_user_standing_penalty({
        usr => $user->id,
        '-or' => [
            {stop_date => undef},
            {stop_date => {'>' => 'now'}}
        ],
        standing_penalty => {
            in => {
                select => {csp => ['id']},
                from => 'csp',
                where => {
                    block_list => ['E-RENEW']
                }
            }
        }
    });

    #check for PATRON_TEMP_RENEWAL
    my $findpenalty_temp = $e->search_config_standing_penalty({name => 'PATRON_TEMP_RENEWAL'})->[0];
    my $searchpenalty_temp = $e->search_actor_user_standing_penalty({
        usr => $user->id,
        standing_penalty => $findpenalty_temp->id,
        '-or' => [
            {stop_date => undef},
            {stop_date => {'>' => 'now'}}
        ]
    });

    if (@$erenew_blocking_penalties) {
        $ctx->{haspenalty} = 1;
    } else {
        $ctx->{haspenalty} = 0;
    }

    if (@$searchpenalty_temp) {
        $ctx->{hastemprenew} = 1;
    } else {
        $ctx->{hastemprenew} = 0;
    }

    return;
}

# PINES - check whether or not to show account renewal link
sub check_account_exp {
    my $self = shift;
    my $ctx = $self->ctx;
    $self->update_dashboard_stats();

    #make sure patron is in an eligible perm group for renewal
    my $grp = new_editor()->retrieve_permission_grp_tree($ctx->{user}->profile);

    if ($grp->erenew eq 't') {
        $ctx->{eligible_permgroup} = 1;
    } else {
        $ctx->{eligible_permgroup} = 0;
    }

    #check for various standing penalties that would block an online renewal
    $self->has_penalties();

    my $home_ou = $ctx->{user}->home_ou;
    $home_ou = ref($home_ou) ? $home_ou->id : $home_ou; # this is not consistently fleshed

    #check for other problems that would block an online renewal
    if ($ctx->{user}->active ne 't') { #user is no longer active
        $ctx->{hasproblem} = 1;
    } elsif ($ctx->{haspenalty} eq 1) { #user has a standing penalty block
        $ctx->{hasproblem} = 1;
    } elsif ($ctx->{user}->barred eq 't') { #user is barred
        $ctx->{hasproblem} = 1;
    } else {
        # check whether the patron has enough current, valid addresses to
        # offer e-renewal
        my $num_addresses_to_check = $self->ctx->{get_org_setting}->(
            $home_ou, 'vendor.quipu.erenew.num_addresses_required'
        ) // 2;
        if ($num_addresses_to_check >= 2) {
            if ($ctx->{valid_billing_address} &&
                $ctx->{valid_mailing_address}) {
                $ctx->{hasproblem} = 0;
            } else {
                $ctx->{hasproblem} = 1;
            }
        } elsif ($num_addresses_to_check == 1) {
            if ($ctx->{valid_billing_address} ||
                $ctx->{valid_mailing_address}) {
                $ctx->{hasproblem} = 0;
            } else {
                $ctx->{hasproblem} = 1;
            }
        } else {
            $ctx->{hasproblem} = 0;
        }
    }

    my $erenewal_offer_window = $self->ctx->{get_org_setting}->(
        $home_ou, "opac.ecard_renewal_offer_interval"
    ) || 29;
    $ctx->{renewal_offer_window} = $erenewal_offer_window;
    my $expire_date = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($ctx->{user}->expire_date));
    if (DateTime->today->add(days=>$erenewal_offer_window) < $expire_date) {
        $ctx->{within_renewal_offer_period} = 0;
    } else {
        $ctx->{within_renewal_offer_period} = 1;
    }

    # The rest of the business logic and the setting of the cache is handled in erenew.tt2 now

    return 1;
}

1;
