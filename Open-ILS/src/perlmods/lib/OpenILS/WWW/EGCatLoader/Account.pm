package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw(md5_hex);
use Data::Dumper;
$Data::Dumper::Indent = 0;
use DateTime;
my $U = 'OpenILS::Application::AppUtils';

sub prepare_extended_user_info {
    my $self = shift;
    my @extra_flesh = @_;
    my $e = $self->editor;

    # are we already in a transaction?
    my $local_xact = !$e->{xact_id}; 
    $e->xact_begin if $local_xact;

    $self->ctx->{user} = $self->editor->retrieve_actor_user([
        $self->ctx->{user}->id,
        {
            flesh => 1,
            flesh_fields => {
                au => [qw/card home_ou addresses ident_type billing_address/, @extra_flesh]
                # ...
            }
        }
    ]);

    $e->rollback if $local_xact;

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
    /;

    my $stat = $self->_load_user_with_prefs;
    return $stat if $stat;

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

    my $now = DateTime->now->strftime('%F');
    foreach my $key (qw/history.circ.retention_start history.hold.retention_start/) {
        my $val = $self->cgi->param($key);
        if($val and $val eq 'on') {
            # Set the start time to 'now' unless a start time already exists for the user
            $settings{$key} = $now unless $$set_map{$key};
        } else {
            # clear the start time if one previously existed for the user
            $settings{$key} = undef if $$set_map{$key};
        }
    }

    # Send the modified settings off to be saved
    $U->simplereq(
        'open-ils.actor', 
        'open-ils.actor.patron.settings.update',
        $self->editor->authtoken, undef, \%settings);

    # re-fetch user prefs 
    $self->ctx->{updated_user_settings} = \%settings;
    return $self->_load_user_with_prefs || Apache2::Const::OK;
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

    if(!$hold_ids) {
        my $circ = OpenSRF::AppSession->create('open-ils.circ');

        $hold_ids = $circ->request(
            'open-ils.circ.holds.id_list.retrieve.authoritative', 
            $e->authtoken, 
            $e->requestor->id
        )->gather(1);
        $circ->kill_me;
    
        $hold_ids = [ grep { defined $_ } @$hold_ids[$offset..($offset + $limit - 1)] ] if $limit or $offset;
    }


    return $hold_ids if $ids_only or @$hold_ids == 0;

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
            # If desired by the caller, filter any holds that are not available.
            if ($available) {
                @collected = grep { $_->{hold}->{status} == 4 } @collected;
            }
            while(my $blob = pop(@collected)) {
                my (undef, @data) = $self->get_records_and_facets(
                    [$blob->{hold}->{bre_id}], undef, {flesh => '{mra}'}
                );
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

    return \@sorted;
}

sub handle_hold_update {
    my $self = shift;
    my $action = shift;
    my $hold_ids = shift;
    my $e = $self->editor;
    my $url;

    my @hold_ids = ($hold_ids) ? @$hold_ids : $self->cgi->param('hold_id'); # for non-_all actions
    @hold_ids = @{$self->fetch_user_holds(undef, 1)} if $action =~ /_all/;

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

            for my $field (qw/expire_time thaw_date/) {
                # XXX TODO make this support other date formats, not just
                # MM/DD/YYYY.
                next unless $self->cgi->param($field) =~
                    m:^(\d{2})/(\d{2})/(\d{4})$:;
                $val->{$field} = "$3-$1-$2";
            }
            $val;
        } @hold_ids;

        $circ->request(
            'open-ils.circ.hold.update.batch.atomic',
            $e->authtoken, undef, \@vals
        )->gather(1);   # LFW XXX test for failure
        $url = $self->ctx->{proto} . '://' . $self->ctx->{hostname} . $self->ctx->{opac_root} . '/myopac/holds';
        foreach my $param (('loc', 'qtype', 'query')) {
            if ($self->cgi->param($param)) {
                $url .= ";$param=" . uri_escape($self->cgi->param($param));
            }
        }
    }

    $circ->kill_me;
    return defined($url) ? $self->generic_redirect($url) : undef;
}

sub load_myopac_holds {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    
    my $limit = $self->cgi->param('limit') || 0;
    my $offset = $self->cgi->param('offset') || 0;
    my $action = $self->cgi->param('action') || '';
    my $hold_id = $self->cgi->param('id');
    my $available = int($self->cgi->param('available') || 0);

    my $hold_handle_result;
    $hold_handle_result = $self->handle_hold_update($action) if $action;

    $ctx->{holds} = $self->fetch_user_holds($hold_id ? [$hold_id] : undef, 0, 1, $available, $limit, $offset);

    return defined($hold_handle_result) ? $hold_handle_result : Apache2::Const::OK;
}

my $data_filler;

sub load_place_hold {
    my $self = shift;
    my $ctx = $self->ctx;
    my $gos = $ctx->{get_org_setting};
    my $e = $self->editor;
    my $cgi = $self->cgi;

    $self->ctx->{page} = 'place_hold';
    my @targets = $cgi->param('hold_target');
    my @parts = $cgi->param('part');

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

    $logger->info("Looking at hold_type: " . $ctx->{hold_type} . " and targets: @targets");

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
        return $hdata;
    };

    my $type_dispatch = {
        T => sub {
            my $recs = $e->batch_retrieve_biblio_record_entry(\@targets, {substream => 1});

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

                # T holds on records that have parts are OK, but if the record has 
                # no non-part copies, the hold will ultimately fail.  When that 
                # happens, require the user to select a part.
                my $part_required = 0;
                if (@$parts) {
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
    # no pickup lib means no holds placement
    return Apache2::Const::OK unless $pickup_lib;

    $ctx->{hold_attempt_made} = 1;

    # Give the original CGI params back to the user in case they
    # want to try to override something.
    $ctx->{orig_params} = $cgi->Vars;
    delete $ctx->{orig_params}{submit};
    delete $ctx->{orig_params}{hold_target};
    delete $ctx->{orig_params}{part};

    my $usr = $e->requestor->id;

    if ($ctx->{is_staff} and !$cgi->param("hold_usr_is_requestor")) {
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

    # First see if we should warn/block for any holds that 
    # might have locally available items.
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

    my $method = 'open-ils.circ.holds.test_and_create.batch';

    if ($cgi->param('override')) {
        $method .= '.override';

    } elsif (!$ctx->{is_staff})  {

        $method .= '.override' if $self->ctx->{get_org_setting}->(
            $e->requestor->home_ou, "opac.patron.auto_overide_hold_events");
    }

    my @create_targets = map {$_->{target_id}} (grep { !$_->{hold_failed} } @hold_data);

    if(@create_targets) {

        my $bses = OpenSRF::AppSession->create('open-ils.circ');
        my $breq = $bses->request( 
            $method, 
            $e->authtoken, 
            $data_filler->({   patronid => $usr,
                pickup_lib => $pickup_lib, 
                hold_type => $hold_type
            }),
            \@create_targets
        );

        while (my $resp = $breq->recv) {

            $resp = $resp->content;
            $logger->info('batch hold placement result: ' . OpenSRF::Utils::JSON->perl2JSON($resp));

            if ($U->event_code($resp)) {
                $ctx->{general_hold_error} = $resp;
                last;
            }

            my ($hdata) = grep {$_->{target_id} eq $resp->{target}} @hold_data;
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
                            $hdata->{could_override} = 1;
                            $hdata->{age_protect} = 1;
                        } else {
                            $hdata->{could_override} = $result->{place_unfillable} || 
                                $self->test_could_override($hdata->{hold_failed_event});
                        }
                    } elsif (ref $result eq 'ARRAY') {
                        $hdata->{hold_failed_event} = $result->[0];

                        if ($result->[3]) { # age_protect_only
                            $hdata->{could_override} = 1;
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
            acp => ['call_number'],
            acn => ['record']
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
    $e->xact_rollback;

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

    $ctx->{circ_history_limit} = $limit;
    $ctx->{circ_history_offset} = $offset;

    my $circ_ids = $e->json_query({
        select => {
            au => [{
                column => 'id', 
                transform => 'action.usr_visible_circs', 
                result_field => 'id'
            }]
        },
        from => 'au',
        where => {id => $e->requestor->id}, 
        limit => $limit,
        offset => $offset
    });

    $ctx->{circs} = $self->fetch_user_circs(1, [map { $_->{id} } @$circ_ids]);
    return Apache2::Const::OK;
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
        where => {id => $e->requestor->id}, 
        limit => $limit,
        offset => $offset
    });

    $ctx->{holds} = $self->fetch_user_holds([map { $_->{id} } @$hold_ids], 0, 1, 0);
    return Apache2::Const::OK;
}

sub load_myopac_payment_form {
    my $self = shift;
    my $r;

    $r = $self->prepare_fines(undef, undef, [$self->cgi->param('xact'), $self->cgi->param('xact_misc')]) and return $r;
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

    return $self->generic_redirect unless @payment_xacts;

    my $cc_args = {"where_process" => 1};

    $cc_args->{$_} = $self->cgi->param($_) for (qw/
        number cvv2 expire_year expire_month billing_first
        billing_last billing_address billing_city billing_state
        billing_zip
    /);

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

    my @total_keys = qw/total_paid total_owed balance_owed/;
    $self->ctx->{"fines"}->{@total_keys} = (0, 0, 0);

    while(my $resp = $req->recv) {
        my $mobts = $resp->content;
        my $circ = $mobts->circulation;

        my $last_billing;
        if($mobts->grocery) {
            my @billings = sort { $a->billing_ts cmp $b->billing_ts } @{$mobts->grocery->billings};
            $last_billing = pop(@billings);
        }

        # XXX TODO confirm that the following, and the later division by 100.0
        # to get a floating point representation once again, is sufficiently
        # "money-safe" math.
        $self->ctx->{"fines"}->{$_} += int($mobts->$_ * 100) for (@total_keys);

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

    $self->ctx->{"fines"}->{$_} /= 100.0 for (@total_keys);
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
        $self->editor->search_actor_usr_note({
            usr => $self->ctx->{user}->id,
            pub => 't'
        })
    );
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

sub _update_bookbag_metadata {
    my ($self, $bookbag) = @_;

    $bookbag->name($self->cgi->param("name"));
    $bookbag->description($self->cgi->param("description"));

    return 1 if $self->editor->update_container_biblio_record_entry_bucket($bookbag);
    return 0;
}

sub load_myopac_bookbags {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $limit = $self->cgi->param('limit') || 10;
    my $offset = $self->cgi->param('offset') || 0;

    $ctx->{bookbags_limit} = $limit;
    $ctx->{bookbags_offset} = $offset;

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
    # XXX add bookbag item paging support

    if ($self->cgi->param("bbid")) {
        my ($bookbag) =
            grep { $_->id eq $self->cgi->param("bbid") } @{$ctx->{bookbags}};

        if ($bookbag) {
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
                            $url .= ";$param=" . uri_escape($self->cgi->param($param));
                        }
                    }

                    return $self->generic_redirect($url);
                }
            }

            # we're done with our CStoreEditor.  Rollback here so 
            # later calls don't cause a timeout, resulting in a 
            # transaction rollback under the covers.
            $e->rollback;

            my $query = $self->_prepare_bookbag_container_query(
                $bookbag->id, $sorter, $modifier
            );

            # XXX Limiting to 1000 for now.  This way you should be able to see entire
            # list contents.  Need to add paging here instead.
            my $args = {
                "limit" => 1000,
                "offset" => 0
            };

            my $items = $U->bib_container_items_via_search($bookbag->id, $query, $args)
                or return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;


            my (undef, @recs) = $self->get_records_and_facets(
                [ map {$_->target_biblio_record_entry->id} @$items ],
                undef, 
                {flesh => '{mra}'}
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
            $self->ctx->{where_from} = $self->ctx->{referer};
            if ( my $anchor = $self->cgi->param('anchor') ) {
                $self->ctx->{where_from} =~ s/#.*|$/#$anchor/;
            }
        }
    }

    # this rollback may be a dupe, but that's OK because 
    # cstoreditor ignores dupe rollbacks
    $e->rollback;

    return Apache2::Const::OK;
}


# actions are create, delete, show, hide, rename, add_rec, delete_item, place_hold
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
    my $name = $cgi->param('name');
    my $description = $cgi->param('description');
    my $success = 0;
    my $list;

    # This url intentionally leaves off the edit_notes parameter, but
    # may need to add some back in for paging.

    my $url = $self->ctx->{proto} . "://" . $self->ctx->{hostname} .
        $self->ctx->{opac_root} . "/myopac/lists?";

    foreach my $param (('loc', 'qtype', 'query', 'sort')) {
        if ($cgi->param($param)) {
            $url .= "$param=" . uri_escape($cgi->param($param)) . ";";
        }
    }

    if ($action eq 'create') {
        $list = Fieldmapper::container::biblio_record_entry_bucket->new;
        $list->name($name);
        $list->description($description);
        $list->owner($e->requestor->id);
        $list->btype('bookbag');
        $list->pub($shared ? 't' : 'f');
        $success = $U->simplereq('open-ils.actor',
            'open-ils.actor.container.create', $e->authtoken, 'biblio', $list);
        if (ref($success) ne 'HASH' && scalar @add_rec) {
            $list_id = (ref($success)) ? $success->id : $success;
            foreach my $add_rec (@add_rec) {
                my $item = Fieldmapper::container::biblio_record_entry_bucket_item->new;
                $item->bucket($list_id);
                $item->target_biblio_record_entry($add_rec);
                $success = $U->simplereq('open-ils.actor',
                                         'open-ils.actor.container.item.create', $e->authtoken, 'biblio', $item);
                last unless $success;
            }
            $url = $cgi->param('where_from') if ($success && $cgi->param('where_from'));
        }
    } elsif($action eq 'place_hold') {

        # @hold_recs comes from anon lists redirect; selected_itesm comes from existing buckets
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
        foreach my $param (('loc', 'qtype', 'query')) {
            if ($cgi->param($param)) {
                $url .= ";$param=" . uri_escape($cgi->param($param));
            }
        }
        return $self->generic_redirect($url);

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
        $url .= "&bbid=" . uri_escape($cgi->param("bbid")) if $cgi->param("bbid");
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

    # XXX FIXME Bucket failure doesn't have a page to show the user anything
    # right now. User just sees a 404 currently.

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

    my $ids = $e->json_query({
        select => {
            au => [{
                column => 'id', 
                transform => 'action.usr_visible_circs', 
                result_field => 'id'
            }]
        },
        from => 'au',
        where => {id => $e->requestor->id} 
    });

    $self->ctx->{csv} = $U->fire_object_event(
        undef, 
        'circ.format.history.csv',
        $e->search_action_circulation({id => [map {$_->{id}} @$ids]}, {substream =>1}),
        $self->editor->requestor->home_ou
    );

    return $self->set_file_download_headers($filename);
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

1;
