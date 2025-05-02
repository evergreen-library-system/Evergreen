package OpenILS::Application::Actor;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use strict; use warnings;
use Data::Dumper;
$Data::Dumper::Indent = 0;
use OpenILS::Event;

use Digest::MD5 qw(md5_hex);

use OpenSRF::EX qw(:try);
use OpenILS::Perm;

use OpenILS::Application::AppUtils;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenSRF::Utils::SettingsClient;

use OpenSRF::Utils::Cache;

use OpenSRF::Utils::JSON;
use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Const qw/:const/;

use OpenILS::Application::Actor::Carousel;
use OpenILS::Application::Actor::Container;
use OpenILS::Application::Actor::ClosedDates;
use OpenILS::Application::Actor::UserGroups;
use OpenILS::Application::Actor::Friends;
use OpenILS::Application::Actor::Stage;
use OpenILS::Application::Actor::Settings;

use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Penalty;
use OpenILS::Utils::BadContact;
use List::Util qw/max reduce/;

use UUID::Tiny qw/:std/;
use HTML::Defang;

sub initialize {
    OpenILS::Application::Actor::Container->initialize();
    OpenILS::Application::Actor::UserGroups->initialize();
    OpenILS::Application::Actor::ClosedDates->initialize();
}

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;

sub _d { warn "Patron:\n" . Dumper(shift()); }

my $cache;
my $set_user_settings;
my $set_ou_settings;


#__PACKAGE__->register_method(
#   method  => "allowed_test",
#   api_name    => "open-ils.actor.allowed_test",
#);
#sub allowed_test {
#    my($self, $conn, $auth, $orgid, $permcode) = @_;
#    my $e = new_editor(authtoken => $auth);
#    return $e->die_event unless $e->checkauth;
#
#    return {
#        orgid => $orgid,
#        permcode => $permcode,
#        result => $e->allowed($permcode, $orgid)
#    };
#}

__PACKAGE__->register_method(
    method  => "update_user_setting",
    api_name    => "open-ils.actor.patron.settings.update",
);
sub update_user_setting {
    my($self, $conn, $auth, $user_id, $settings) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    $user_id = $e->requestor->id unless defined $user_id;

    unless($e->requestor->id == $user_id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;
        return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);
    }

    for my $name (keys %$settings) {
        my $val = $$settings{$name};
        my $set = $e->search_actor_user_setting({usr => $user_id, name => $name})->[0];

        if(defined $val) {
            $val = OpenSRF::Utils::JSON->perl2JSON($val);
            if($set) {
                $set->value($val);
                $e->update_actor_user_setting($set) or return $e->die_event;
            } else {
                $set = Fieldmapper::actor::user_setting->new;
                $set->usr($user_id);
                $set->name($name);
                $set->value($val);
                $e->create_actor_user_setting($set) or return $e->die_event;
            }
        } elsif($set) {
            $e->delete_actor_user_setting($set) or return $e->die_event;
        }
    }

    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
    method    => "update_privacy_waiver",
    api_name  => "open-ils.actor.patron.privacy_waiver.update",
    signature => {
        desc => "Replaces any existing privacy waiver entries for the patron with the supplied values.",
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'User ID', type => 'number'},
            {desc => 'Arrayref of privacy waiver entries', type => 'object'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);
sub update_privacy_waiver {
    my($self, $conn, $auth, $user_id, $waiver) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    $user_id = $e->requestor->id unless defined $user_id;

    unless($e->requestor->id == $user_id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;
        return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);
    }

    foreach my $w (@$waiver) {
        $w->{usr} = $user_id unless $w->{usr};
        if ($w->{id} && $w->{id} ne 'new') {
            my $existing_rows = $e->search_actor_usr_privacy_waiver({usr => $user_id, id => $w->{id}});
            if ($existing_rows) {
                my $existing = $existing_rows->[0];
                # delete existing if name is empty
                if (!$w->{name} or $w->{name} =~ /^\s*$/) {
                    $e->delete_actor_usr_privacy_waiver($existing) or return $e->die_event;

                # delete existing if none of the boxes were checked
                } elsif (!$w->{place_holds} && !$w->{pickup_holds} && !$w->{checkout_items} && !$w->{view_history}) {
                    $e->delete_actor_usr_privacy_waiver($existing) or return $e->die_event;

                # otherwise, update existing waiver entry
                } else {
                    $existing->name($w->{name});
                    $existing->place_holds($w->{place_holds});
                    $existing->pickup_holds($w->{pickup_holds});
                    $existing->checkout_items($w->{checkout_items});
                    $existing->view_history($w->{view_history});
                    $e->update_actor_usr_privacy_waiver($existing) or return $e->die_event;
                }
            } else {
                $logger->warn("No privacy waiver entry found for user $user_id with ID " . $w->{id});
            }

        } else {
            # ignore new entries with empty name or with no boxes checked
            next if (!$w->{name} or $w->{name} =~ /^\s*$/);
            next if (!$w->{place_holds} && !$w->{pickup_holds} && !$w->{checkout_items} && !$w->{view_history});
            my $new = Fieldmapper::actor::usr_privacy_waiver->new;
            $new->usr($w->{usr});
            $new->name($w->{name});
            $new->place_holds($w->{place_holds});
            $new->pickup_holds($w->{pickup_holds});
            $new->checkout_items($w->{checkout_items});
            $new->view_history($w->{view_history});
            $e->create_actor_usr_privacy_waiver($new) or return $e->die_event;
        }
    }

    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method    => "get_ou_setting_history",
    api_name  => "open-ils.actor.org_unit.settings.history.retrieve",
    signature => {
        desc => "Retrieves the history of an Org Unit Setting.  The permission to retrieve "          .
                "an org unit setting's history is dependant on a specific permission specified "       .
                "in the view_perm column of the config.org_unit_setting_type " .
                "table's row corresponding to the setting being changed." ,
        params => [
            {desc => 'Authentication token',        type => 'string'},
            {desc => 'Org Unit ID',                 type => 'number'},
            {desc => 'Setting Type Name',           type => 'string'}
        ],
        return => {desc => 'History IDL Object'}
    }
);

sub get_ou_setting_history {
    my( $self, $client, $auth, $setting, $orgid ) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    return $U->ou_ancestor_setting_log(
        $orgid, $setting, $e, $auth
    );

}

__PACKAGE__->register_method(
    method    => "set_ou_settings",
    api_name  => "open-ils.actor.org_unit.settings.update",
    signature => {
        desc => "Updates the value for a given org unit setting.  The permission to update "          .
                "an org unit setting is either the UPDATE_ORG_UNIT_SETTING_ALL, or a specific "       .
                "permission specified in the update_perm column of the config.org_unit_setting_type " .
                "table's row corresponding to the setting being changed." ,
        params => [
            {desc => 'Authentication token',             type => 'string'},
            {desc => 'Org unit ID',                      type => 'number'},
            {desc => 'Hash of setting name-value pairs', type => 'object'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub set_ou_settings {
    my( $self, $client, $auth, $org_id, $settings ) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    my $defang = HTML::Defang->new;

    my $all_allowed = $e->allowed("UPDATE_ORG_UNIT_SETTING_ALL", $org_id);

    for my $name (keys %$settings) {
        my $val = $$settings{$name};
        if ($name eq 'opac.patron.custom_css') { $val = $defang->defang($val); }

        my $type = $e->retrieve_config_org_unit_setting_type([
            $name,
            {flesh => 1, flesh_fields => {'coust' => ['update_perm']}}
        ]) or return $e->die_event;
        my $set = $e->search_actor_org_unit_setting({org_unit => $org_id, name => $name})->[0];

        # If there is no relevant permission, the default assumption will
        # be, "no, the caller cannot change that value."
        return $e->die_event unless ($all_allowed ||
            ($type->update_perm && $e->allowed($type->update_perm->code, $org_id)));

        if(defined $val) {
            $val = OpenSRF::Utils::JSON->perl2JSON($val);
            if($set) {
                $set->value($val);
                $e->update_actor_org_unit_setting($set) or return $e->die_event;
            } else {
                $set = Fieldmapper::actor::org_unit_setting->new;
                $set->org_unit($org_id);
                $set->name($name);
                $set->value($val);
                $e->create_actor_org_unit_setting($set) or return $e->die_event;
            }
        } elsif($set) {
            $e->delete_actor_org_unit_setting($set) or return $e->die_event;
        }
    }

    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method    => "fetch_visible_ou_settings_log",
    api_name  => "open-ils.actor.org_unit.settings.history.visible.retrieve",
    signature => {
        desc => "Retrieves the log entries for the specified OU setting. " .
                "If the setting has a view permission, the results are limited " .
                "to entries at the OUs that the user has the view permission. ",
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Setting name',         type => 'string'}
        ],
        return => {desc => 'List of fieldmapper objects of the log entries, Event on error'}
    }
);

sub fetch_visible_ou_settings_log {
    my( $self, $client, $auth, $setting ) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->die_event unless $e->allowed("STAFF_LOGIN");
    return OpenILS::Event->new('BAD_PARAMS') unless defined($setting);

    my $type = $e->retrieve_config_org_unit_setting_type([
        $setting,
        {flesh => 1, flesh_fields => {coust => ['view_perm']}}
    ]);
    return OpenILS::Event->new('BAD_PARAMS', note => 'setting type not found')
        unless $type;

    my $query = { field_name => $setting };
    if ($type->view_perm) {
        $query->{org} = $U->user_has_work_perm_at($e, $type->view_perm->code, {descendants => 1});
        if (scalar @{ $query->{org} } == 0) {
            # user doesn't have the view permission anywhere, so return nothing
            return [];
        }
    }

    my $results = $e->search_config_org_unit_setting_type_log([$query, {'order_by' => 'date_applied ASC'}])
        or return $e->die_event;
    return $results;
}

__PACKAGE__->register_method(
    method   => "user_settings",
    authoritative => 1,
    api_name => "open-ils.actor.patron.settings.retrieve",
);
sub user_settings {
    my( $self, $client, $auth, $user_id, $setting ) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    $user_id = $e->requestor->id unless defined $user_id;

    my $patron = $e->retrieve_actor_user($user_id) or return $e->event;
    if($e->requestor->id != $user_id) {
        return $e->event unless $e->allowed('VIEW_USER', $patron->home_ou);
    }

    sub get_setting {
        my($e, $user_id, $setting) = @_;
        my $val = $e->search_actor_user_setting({usr => $user_id, name => $setting})->[0];
        return undef unless $val; # XXX this should really return undef, but needs testing
        return OpenSRF::Utils::JSON->JSON2perl($val->value);
    }

    if($setting) {
        if(ref $setting eq 'ARRAY') {
            my %settings;
            $settings{$_} = get_setting($e, $user_id, $_) for @$setting;
            return \%settings;
        } else {
            return get_setting($e, $user_id, $setting);
        }
    } else {
        my $s = $e->search_actor_user_setting({usr => $user_id});
        return { map { ( $_->name => OpenSRF::Utils::JSON->JSON2perl($_->value) ) } @$s };
    }
}


__PACKAGE__->register_method(
    method    => "ranged_ou_settings",
    api_name  => "open-ils.actor.org_unit_setting.values.ranged.retrieve",
    signature => {
        desc   => "Retrieves all org unit settings for the given org_id, up to whatever limit " .
                "is implied for retrieving OU settings by the authenticated users' permissions.",
        params => [
            {desc => 'Authentication token',   type => 'string'},
            {desc => 'Org unit ID',            type => 'number'},
        ],
        return => {desc => 'A hashref of "ranged" settings, event on error'}
    }
);
sub ranged_ou_settings {
    my( $self, $client, $auth, $org_id ) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my %ranged_settings;
    my $org_list = $U->get_org_ancestors($org_id);
    my $settings = $e->search_actor_org_unit_setting({org_unit => $org_list});
    $org_list = [ reverse @$org_list ];

    # start at the context org and capture the setting value
    # without clobbering settings we've already captured
    for my $this_org_id (@$org_list) {

        my @sets = grep { $_->org_unit == $this_org_id } @$settings;

        for my $set (@sets) {
            my $type = $e->retrieve_config_org_unit_setting_type([
                $set->name,
                {flesh => 1, flesh_fields => {coust => ['view_perm']}}
            ]);

            # If there is no relevant permission, the default assumption will
            # be, "yes, the caller can have that value."
            if ($type && $type->view_perm) {
                next if not $e->allowed($type->view_perm->code, $org_id);
            }

            $ranged_settings{$set->name} = OpenSRF::Utils::JSON->JSON2perl($set->value)
                unless defined $ranged_settings{$set->name};
        }
    }

    return \%ranged_settings;
}



__PACKAGE__->register_method(
    api_name  => 'open-ils.actor.ou_setting.ancestor_default',
    method    => 'ou_ancestor_setting',
    signature => {
        desc => 'Get the org unit setting value associated with the setting name as seen from the specified org unit.  ' .
                'This method will make sure that the given user has permission to view that setting, if there is a '     .
                'permission associated with the setting.  If a permission is required and no authtoken is given, or '     .
                'the user lacks the permisssion, undef will be returned.'       ,
        params => [
            { desc => 'Org unit ID',          type => 'number' },
            { desc => 'setting name',         type => 'string' },
            { desc => 'authtoken (optional)', type => 'string' }
        ],
        return => {desc => 'A value for the org unit setting, or undef'}
    }
);

# ------------------------------------------------------------------
# Attempts to find the org setting value for a given org.  if not
# found at the requested org, searches up the org tree until it
# finds a parent that has the requested setting.
# when found, returns { org => $id, value => $value }
# otherwise, returns NULL
# ------------------------------------------------------------------
sub ou_ancestor_setting {
    my( $self, $client, $orgid, $name, $auth ) = @_;
    # Make sure $auth is set to something if not given.
    $auth ||= -1;
    return $U->ou_ancestor_setting($orgid, $name, undef, $auth);
}

__PACKAGE__->register_method(
    api_name  => 'open-ils.actor.ou_setting.ancestor_default.batch',
    method    => 'ou_ancestor_setting_batch',
    signature => {
        desc => 'Get org unit setting name => value pairs for a list of names, as seen from the specified org unit.  ' .
                'This method will make sure that the given user has permission to view that setting, if there is a '     .
                'permission associated with the setting.  If a permission is required and no authtoken is given, or '     .
                'the user lacks the permisssion, undef will be returned.'       ,
        params => [
            { desc => 'Org unit ID',          type => 'number' },
            { desc => 'setting name list',    type => 'array'  },
            { desc => 'authtoken (optional)', type => 'string' }
        ],
        return => {desc => 'A hash with name => value pairs for the org unit settings'}
    }
);
sub ou_ancestor_setting_batch {
    my( $self, $client, $orgid, $name_list, $auth ) = @_;

    # splitting the list of settings to fetch values
    # so that ones that *don't* require view_perm checks
    # can be fetched in one fell swoop, which is
    # significantly faster in cases where a large
    # number of settings need to be fetched.
    my %perm_check_required = ();
    my @perm_check_not_required = ();

    # Note that ->ou_ancestor_setting also can check
    # to see if the setting has a view_perm, but testing
    # suggests that the redundant checks do not significantly
    # increase the time it takes to fetch the values of
    # permission-controlled settings.
    my $e = new_editor();
    my $res = $e->search_config_org_unit_setting_type({
        name      => $name_list,
        view_perm => { "!=" => undef },
    });
    %perm_check_required = map { $_->name() => 1 } @$res;
    foreach my $setting (@$name_list) {
        push @perm_check_not_required, $setting
            unless exists($perm_check_required{$setting});
    }

    my %values;
    if (@perm_check_not_required) {
        %values = $U->ou_ancestor_setting_batch_insecure($orgid, \@perm_check_not_required);
    }
    $values{$_} = $U->ou_ancestor_setting(
        $orgid, $_, undef,
        ($auth ? $auth : -1)
    ) for keys(%perm_check_required);
    return \%values;
}



__PACKAGE__->register_method(
    method   => "update_patron",
    api_name => "open-ils.actor.patron.update",
    signature => {
        desc   => q/
            Update an existing user, or create a new one.  Related objects,
            like cards, addresses, survey responses, and stat cats,
            can be updated by attaching them to the user object in their
            respective fields.  For examples, the billing address object
            may be inserted into the 'billing_address' field, etc.  For each
            attached object, indicate if the object should be created,
            updated, or deleted using the built-in 'isnew', 'ischanged',
            and 'isdeleted' fields on the object.
            This method intentionally does not handle updates to patron
            notes, user activity, and standing penalties; if any values
            are supplied for those fields in the patron data object,
            they will be ignored. Please refer to bug 1976126 before
            changing this.
        /,
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Patron data object',   type => 'object' }
        ],
        return => {desc => 'A fleshed user object, event on error'}
    }
);

sub update_patron {
    my( $self, $client, $auth, $patron ) = @_;

    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->event unless $e->checkauth;

    $logger->info($patron->isnew ? "Creating new patron..." :
        "Updating Patron: " . $patron->id);

    my $evt = check_group_perm($e, $e->requestor, $patron);
    return $evt if $evt;

    # $new_patron is the patron in progress.  $patron is the original patron
    # passed in with the method.  new_patron will change as the components
    # of patron are added/updated.

    my $new_patron;

    # unflesh the real items on the patron
    $patron->card( $patron->card->id ) if(ref($patron->card));
    $patron->billing_address( $patron->billing_address->id )
        if(ref($patron->billing_address));
    $patron->mailing_address( $patron->mailing_address->id )
        if(ref($patron->mailing_address));

    # create/update the patron first so we can use his id

    # $patron is the obj from the client (new data) and $new_patron is the
    # patron object properly built for db insertion, so we need a third variable
    # if we want to represent the old patron.

    my $old_patron;
    my $barred_hook = '';
    my $renew_hook = '';

    if($patron->isnew()) {
        ( $new_patron, $evt ) = _add_patron($e, _clone_patron($patron));
        return $evt if $evt;
        if($U->is_true($patron->barred)) {
            return $e->die_event unless
                $e->allowed('BAR_PATRON', $patron->home_ou);
        }
        if(($patron->photo_url)) {
            return $e->die_event unless
                $e->allowed('UPDATE_USER_PHOTO_URL', $patron->home_ou);
        }
    } else {
        $new_patron = $patron;

        # Did auth checking above already.
        $old_patron = $e->retrieve_actor_user($patron->id) or
            return $e->die_event;

        $renew_hook = 'au.renewed' if ($old_patron->expire_date ne $new_patron->expire_date);

        if($U->is_true($old_patron->barred) != $U->is_true($new_patron->barred)) {
            my $perm = $U->is_true($old_patron->barred) ? 'UNBAR_PATRON' : 'BAR_PATRON';
            return $e->die_event unless $e->allowed($perm, $patron->home_ou);

            $barred_hook = $U->is_true($new_patron->barred) ?
                'au.barred' : 'au.unbarred';
        }

        if($old_patron->photo_url ne $new_patron->photo_url) {
            my $perm = 'UPDATE_USER_PHOTO_URL';
            return $e->die_event unless $e->allowed($perm, $patron->home_ou);
        }

        # update the password by itself to avoid the password protection magic
        if ($patron->passwd && $patron->passwd ne $old_patron->passwd) {
            modify_migrated_user_password($e, $patron->id, $patron->passwd);
            $new_patron->passwd(''); # subsequent update will set
                                     # actor.usr.passwd to MD5('')
        }
    }

    ( $new_patron, $evt ) = _add_update_addresses($e, $patron, $new_patron);
    return $evt if $evt;

    ( $new_patron, $evt ) = _add_update_cards($e, $patron, $new_patron);
    return $evt if $evt;

    ( $new_patron, $evt ) = _add_update_waiver_entries($e, $patron, $new_patron);
    return $evt if $evt;

    ( $new_patron, $evt ) = _add_survey_responses($e, $patron, $new_patron);
    return $evt if $evt;

    # re-update the patron if anything has happened to him during this process
    if($new_patron->ischanged()) {
        ( $new_patron, $evt ) = _update_patron($e, $new_patron);
        return $evt if $evt;
    }

    ( $new_patron, $evt ) = _clear_badcontact_penalties($e, $old_patron, $new_patron);
    return $evt if $evt;

    ($new_patron, $evt) = _create_stat_maps($e, $patron, $new_patron);
    return $evt if $evt;

    ($new_patron, $evt) = _create_perm_maps($e, $patron, $new_patron);
    return $evt if $evt;

    $evt = apply_invalid_addr_penalty($e, $patron);
    return $evt if $evt;

    $e->commit;

    my $tses = OpenSRF::AppSession->create('open-ils.trigger');
    if($patron->isnew) {
        $tses->request('open-ils.trigger.event.autocreate',
            'au.created', $new_patron, $new_patron->home_ou);
    } else {
        $tses->request('open-ils.trigger.event.autocreate',
            'au.updated', $new_patron, $new_patron->home_ou);

        $tses->request('open-ils.trigger.event.autocreate', $renew_hook,
            $new_patron, $new_patron->home_ou) if $renew_hook;

        $tses->request('open-ils.trigger.event.autocreate', $barred_hook,
            $new_patron, $new_patron->home_ou) if $barred_hook;
    }

    $e->xact_begin; # $e->rollback is called in new_flesh_user
    return flesh_user($new_patron->id(), $e);
}

sub apply_invalid_addr_penalty {
    my $e = shift;
    my $patron = shift;

    # grab the invalid address penalty if set
    my $penalties = OpenILS::Utils::Penalty->retrieve_usr_penalties($e, $patron->id, $patron->home_ou);

    my ($addr_penalty) = grep
        { $_->standing_penalty->name eq 'INVALID_PATRON_ADDRESS' } @$penalties;

    # do we enforce invalid address penalty
    my $enforce = $U->ou_ancestor_setting_value(
        $patron->home_ou, 'circ.patron_invalid_address_apply_penalty') || 0;

    my $addrs = $e->search_actor_user_address(
        {usr => $patron->id, valid => 'f', id => {'>' => 0}}, {idlist => 1});
    my $addr_count = scalar(@$addrs);

    if($addr_count == 0 and $addr_penalty) {

        # regardless of any settings, remove the penalty when the user has no invalid addresses
        $e->delete_actor_user_standing_penalty($addr_penalty) or return $e->die_event;
        $e->commit;

    } elsif($enforce and $addr_count > 0 and !$addr_penalty) {

        my $ptype = $e->retrieve_config_standing_penalty(29) or return $e->die_event;
        my $depth = $ptype->org_depth;
        my $ctx_org = $U->org_unit_ancestor_at_depth($patron->home_ou, $depth) if defined $depth;
        $ctx_org = $patron->home_ou unless defined $ctx_org;

        my $penalty = Fieldmapper::actor::user_standing_penalty->new;
        $penalty->usr($patron->id);
        $penalty->org_unit($ctx_org);
        $penalty->standing_penalty(OILS_PENALTY_INVALID_PATRON_ADDRESS);

        $e->create_actor_user_standing_penalty($penalty) or return $e->die_event;
    }

    return undef;
}


sub flesh_user {
    my $id = shift;
    my $e = shift;
    my $home_ou = shift;

    my $fields = [
        "cards",
        "card",
        "standing_penalties",
        "settings",
        "addresses",
        "billing_address",
        "mailing_address",
        "stat_cat_entries",
        "waiver_entries",
        "settings",
        "usr_activity"
    ];
    push @$fields, "home_ou" if $home_ou;
    return new_flesh_user($id, $fields, $e );
}






# clone and clear stuff that would break the database
sub _clone_patron {
    my $patron = shift;

    my $new_patron = $patron->clone;
    # clear these
    $new_patron->clear_billing_address();
    $new_patron->clear_mailing_address();
    $new_patron->clear_addresses();
    $new_patron->clear_card();
    $new_patron->clear_cards();
    $new_patron->clear_id();
    $new_patron->clear_isnew();
    $new_patron->clear_ischanged();
    $new_patron->clear_isdeleted();
    $new_patron->clear_stat_cat_entries();
    $new_patron->clear_waiver_entries();
    $new_patron->clear_permissions();
    $new_patron->clear_standing_penalties();

    return $new_patron;
}


sub _add_patron {

    my $e          = shift;
    my $patron      = shift;

    return (undef, $e->die_event) unless
        $e->allowed('CREATE_USER', $patron->home_ou);

    my $ex = $e->search_actor_user(
        {usrname => $patron->usrname}, {idlist => 1});
    return (undef, OpenILS::Event->new('USERNAME_EXISTS')) if @$ex;

    $logger->info("Creating new user in the DB with username: ".$patron->usrname());

    # do a dance to get the password hashed securely
    my $saved_password = $patron->passwd;
    $patron->passwd('');
    $e->create_actor_user($patron) or return (undef, $e->die_event);
    modify_migrated_user_password($e, $patron->id, $saved_password);

    my $id = $patron->id; # added by CStoreEditor

    $logger->info("Successfully created new user [$id] in DB");
    return ($e->retrieve_actor_user($id), undef);
}


sub check_group_perm {
    my( $e, $requestor, $patron ) = @_;
    my $evt;

    # first let's see if the requestor has
    # priveleges to update this user in any way
    if( ! $patron->isnew ) {
        my $p = $e->retrieve_actor_user($patron->id);

        # If we are the requestor (trying to update our own account)
        # and we are not trying to change our profile, we're good
        if( $p->id == $requestor->id and
                $p->profile == $patron->profile ) {
            return undef;
        }


        $evt = group_perm_failed($e, $requestor, $p);
        return $evt if $evt;
    }

    # They are allowed to edit this patron.. can they put the
    # patron into the group requested?
    $evt = group_perm_failed($e, $requestor, $patron);
    return $evt if $evt;
    return undef;
}


sub group_perm_failed {
    my( $e, $requestor, $patron ) = @_;

    my $perm;
    my $grp;
    my $grpid = $patron->profile;

    do {

        $logger->debug("user update looking for group perm for group $grpid");
        $grp = $e->retrieve_permission_grp_tree($grpid);

    } while( !($perm = $grp->application_perm) and ($grpid = $grp->parent) );

    $logger->info("user update checking perm $perm on user ".
        $requestor->id." for update/create on user username=".$patron->usrname);

    return $e->allowed($perm, $patron->home_ou) ? undef : $e->die_event;
}



sub _update_patron {
    my( $e, $patron, $noperm) = @_;

    $logger->info("Updating patron ".$patron->id." in DB");

    my $evt;

    if(!$noperm) {
        return (undef, $e->die_event)
            unless $e->allowed('UPDATE_USER', $patron->home_ou);
    }

    if(!$patron->ident_type) {
        $patron->clear_ident_type;
        $patron->clear_ident_value;
    }

    $evt = verify_last_xact($e, $patron);
    return (undef, $evt) if $evt;

    $e->update_actor_user($patron) or return (undef, $e->die_event);

    # re-fetch the user to pick up the latest last_xact_id value
    # to avoid collisions.
    $patron = $e->retrieve_actor_user($patron->id);

    return ($patron);
}

sub verify_last_xact {
    my( $e, $patron ) = @_;
    return undef unless $patron->id and $patron->id > 0;
    my $p = $e->retrieve_actor_user($patron->id);
    my $xact = $p->last_xact_id;
    return undef unless $xact;
    $logger->info("user xact = $xact, saving with xact " . $patron->last_xact_id);
    return OpenILS::Event->new('XACT_COLLISION')
        if $xact ne $patron->last_xact_id;
    return undef;
}


sub _check_dup_ident {
    my( $session, $patron ) = @_;

    return undef unless $patron->ident_value;

    my $search = {
        ident_type  => $patron->ident_type,
        ident_value => $patron->ident_value,
    };

    $logger->debug("patron update searching for dup ident values: " .
        $patron->ident_type . ':' . $patron->ident_value);

    $search->{id} = {'!=' => $patron->id} if $patron->id and $patron->id > 0;

    my $dups = $session->request(
        'open-ils.storage.direct.actor.user.search_where.atomic', $search )->gather(1);


    return OpenILS::Event->new('PATRON_DUP_IDENT1', payload => $patron )
        if $dups and @$dups;

    return undef;
}


sub _add_update_addresses {

    my $e = shift;
    my $patron = shift;
    my $new_patron = shift;

    my $evt;

    my $current_id; # id of the address before creation

    my $addresses = $patron->addresses();

    for my $address (@$addresses) {

        next unless ref $address;
        $current_id = $address->id();

        if( $patron->billing_address() and
            $patron->billing_address() == $current_id ) {
            $logger->info("setting billing addr to $current_id");
            $new_patron->billing_address($address->id());
            $new_patron->ischanged(1);
        }

        if( $patron->mailing_address() and
            $patron->mailing_address() == $current_id ) {
            $new_patron->mailing_address($address->id());
            $logger->info("setting mailing addr to $current_id");
            $new_patron->ischanged(1);
        }


        if($address->isnew()) {

            $address->usr($new_patron->id());

            ($address, $evt) = _add_address($e,$address);
            return (undef, $evt) if $evt;

            # we need to get the new id
            if( $patron->billing_address() and
                    $patron->billing_address() == $current_id ) {
                $new_patron->billing_address($address->id());
                $logger->info("setting billing addr to $current_id");
                $new_patron->ischanged(1);
            }

            if( $patron->mailing_address() and
                    $patron->mailing_address() == $current_id ) {
                $new_patron->mailing_address($address->id());
                $logger->info("setting mailing addr to $current_id");
                $new_patron->ischanged(1);
            }

        } elsif($address->ischanged() ) {

            ($address, $evt) = _update_address($e, $address);
            return (undef, $evt) if $evt;

        } elsif($address->isdeleted() ) {

            if( $address->id() == $new_patron->mailing_address() ) {
                $new_patron->clear_mailing_address();
                ($new_patron, $evt) = _update_patron($e, $new_patron);
                return (undef, $evt) if $evt;
            }

            if( $address->id() == $new_patron->billing_address() ) {
                $new_patron->clear_billing_address();
                ($new_patron, $evt) = _update_patron($e, $new_patron);
                return (undef, $evt) if $evt;
            }

            $evt = _delete_address($e, $address);
            return (undef, $evt) if $evt;
        }
    }

    return ( $new_patron, undef );
}


# adds an address to the db and returns the address with new id
sub _add_address {
    my($e, $address) = @_;
    $address->clear_id();

    $logger->info("Creating new address at street ".$address->street1);

    # put the address into the database
    $e->create_actor_user_address($address) or return (undef, $e->die_event);
    return ($address, undef);
}


sub _update_address {
    my( $e, $address ) = @_;

    $logger->info("Updating address ".$address->id." in the DB");

    $e->update_actor_user_address($address) or return (undef, $e->die_event);

    return ($address, undef);
}



sub _add_update_cards {

    my $e = shift;
    my $patron = shift;
    my $new_patron = shift;

    my $evt;

    my $virtual_id; #id of the card before creation

    my $card_changed = 0;
    my $cards = $patron->cards();
    for my $card (@$cards) {

        $card->usr($new_patron->id());

        if(ref($card) and $card->isnew()) {

            $virtual_id = $card->id();
            ( $card, $evt ) = _add_card($e, $card);
            return (undef, $evt) if $evt;

            #if(ref($patron->card)) { $patron->card($patron->card->id); }
            if($patron->card() == $virtual_id) {
                $new_patron->card($card->id());
                $new_patron->ischanged(1);
            }
            $card_changed++;

        } elsif( ref($card) and $card->ischanged() ) {
            $evt = _update_card($e, $card);
            return (undef, $evt) if $evt;
            $card_changed++;
        }
    }

    $U->create_events_for_hook('au.barcode_changed', $new_patron, $e->requestor->ws_ou)
        if $card_changed;

    return ( $new_patron, undef );
}


# adds an card to the db and returns the card with new id
sub _add_card {
    my( $e, $card ) = @_;
    $card->clear_id();

    $logger->info("Adding new patron card ".$card->barcode);

    $e->create_actor_card($card) or return (undef, $e->die_event);

    return ( $card, undef );
}


# returns event on error.  returns undef otherwise
sub _update_card {
    my( $e, $card ) = @_;
    $logger->info("Updating patron card ".$card->id);

    $e->update_actor_card($card) or return $e->die_event;
    return undef;
}


sub _add_update_waiver_entries {
    my $e = shift;
    my $patron = shift;
    my $new_patron = shift;
    my $evt;

    my $waiver_entries = $patron->waiver_entries();
    for my $waiver (@$waiver_entries) {
        next unless ref $waiver;
        $waiver->usr($new_patron->id());
        if ($waiver->isnew()) {
            next if (!$waiver->name() or $waiver->name() =~ /^\s*$/);
            next if (!$waiver->place_holds() && !$waiver->pickup_holds() && !$waiver->checkout_items() && !$waiver->view_history());
            $logger->info("Adding new patron waiver entry");
            $waiver->clear_id();
            $e->create_actor_usr_privacy_waiver($waiver) or return (undef, $e->die_event);
        } elsif ($waiver->ischanged()) {
            $logger->info("Updating patron waiver entry " . $waiver->id);
            $e->update_actor_usr_privacy_waiver($waiver) or return (undef, $e->die_event);
        } elsif ($waiver->isdeleted()) {
            $logger->info("Deleting patron waiver entry " . $waiver->id);
            $e->delete_actor_usr_privacy_waiver($waiver) or return (undef, $e->die_event);
        }
    }
    return ($new_patron, undef);
}


# returns event on error.  returns undef otherwise
sub _delete_address {
    my( $e, $address ) = @_;

    $logger->info("Deleting address ".$address->id." from DB");

    $e->delete_actor_user_address($address) or return $e->die_event;
    return undef;
}



sub _add_survey_responses {
    my ($e, $patron, $new_patron) = @_;

    $logger->info( "Updating survey responses for patron ".$new_patron->id );

    my $responses = $patron->survey_responses;

    if($responses) {

        $_->usr($new_patron->id) for (@$responses);

        my $evt = $U->simplereq( "open-ils.circ",
            "open-ils.circ.survey.submit.user_id", $responses );

        return (undef, $evt) if defined($U->event_code($evt));

    }

    return ( $new_patron, undef );
}

sub _clear_badcontact_penalties {
    my ($e, $old_patron, $new_patron) = @_;

    return ($new_patron, undef) unless $old_patron;

    my $PNM = $OpenILS::Utils::BadContact::PENALTY_NAME_MAP;

    # This ignores whether the caller of update_patron has any permission
    # to remove penalties, but these penalties no longer make sense
    # if an email address field (for example) is changed (and the caller must
    # have perms to do *that*) so there's no reason not to clear the penalties.

    my $bad_contact_penalties = $e->search_actor_user_standing_penalty([
        {
            "+csp" => {"name" => [values(%$PNM)]},
            "+ausp" => {"stop_date" => undef, "usr" => $new_patron->id}
        }, {
            "join" => {"csp" => {}},
            "flesh" => 1,
            "flesh_fields" => {"ausp" => ["standing_penalty"]}
        }
    ]) or return (undef, $e->die_event);

    return ($new_patron, undef) unless @$bad_contact_penalties;

    my @penalties_to_clear;
    my ($field, $penalty_name);

    # For each field that might have an associated bad contact penalty,
    # check for such penalties and add them to the to-clear list if that
    # field has changed.
    while (($field, $penalty_name) = each(%$PNM)) {
        if ($old_patron->$field ne $new_patron->$field) {
            push @penalties_to_clear, grep {
                $_->standing_penalty->name eq $penalty_name
            } @$bad_contact_penalties;
        }
    }

    foreach (@penalties_to_clear) {
        # Note that this "archives" penalties, in the terminology of the staff
        # client, instead of just deleting them.  This may assist reporting,
        # or preserving old contact information when it is still potentially
        # of interest.
        $_->standing_penalty($_->standing_penalty->id); # deflesh
        $_->stop_date('now');
        $e->update_actor_user_standing_penalty($_) or return (undef, $e->die_event);
    }

    return ($new_patron, undef);
}


sub _create_stat_maps {

    my($e, $patron, $new_patron) = @_;

    my $maps = $patron->stat_cat_entries();

    for my $map (@$maps) {

        my $method = "update_actor_stat_cat_entry_user_map";

        if ($map->isdeleted()) {
            $method = "delete_actor_stat_cat_entry_user_map";

        } elsif ($map->isnew()) {
            $method = "create_actor_stat_cat_entry_user_map";
            $map->clear_id;
        }


        $map->target_usr($new_patron->id);

        $logger->info("Updating stat entry with method $method and map $map");

        $e->$method($map) or return (undef, $e->die_event);
    }

    return ($new_patron, undef);
}

sub _create_perm_maps {

    my($e, $patron, $new_patron) = @_;

    my $maps = $patron->permissions;

    for my $map (@$maps) {

        my $method = "update_permission_usr_perm_map";
        if ($map->isdeleted()) {
            $method = "delete_permission_usr_perm_map";
        } elsif ($map->isnew()) {
            $method = "create_permission_usr_perm_map";
            $map->clear_id;
        }

        $map->usr($new_patron->id);

        $logger->info( "Updating permissions with method $method and map $map" );

        $e->$method($map) or return (undef, $e->die_event);
    }

    return ($new_patron, undef);
}


__PACKAGE__->register_method(
    method   => "set_user_work_ous",
    api_name => "open-ils.actor.user.work_ous.update",
);

sub set_user_work_ous {
    my $self   = shift;
    my $client = shift;
    my $ses    = shift;
    my $maps   = shift;

    my( $requestor, $evt ) = $apputils->checksesperm( $ses, 'ASSIGN_WORK_ORG_UNIT' );
    return $evt if $evt;

    my $session = $apputils->start_db_session();
    $apputils->set_audit_info($session, $ses, $requestor->id, $requestor->wsid);

    for my $map (@$maps) {

        my $method = "open-ils.storage.direct.permission.usr_work_ou_map.update";
        if ($map->isdeleted()) {
            $method = "open-ils.storage.direct.permission.usr_work_ou_map.delete";
        } elsif ($map->isnew()) {
            $method = "open-ils.storage.direct.permission.usr_work_ou_map.create";
            $map->clear_id;
        }

        #warn( "Updating permissions with method $method and session $ses and map $map" );
        $logger->info( "Updating work_ou map with method $method and map $map" );

        my $stat = $session->request($method, $map)->gather(1);
        $logger->warn( "update failed: ".$U->DB_UPDATE_FAILED($map) ) unless defined($stat);

    }

    $apputils->commit_db_session($session);

    return scalar(@$maps);
}


__PACKAGE__->register_method(
    method   => "set_user_perms",
    api_name => "open-ils.actor.user.permissions.update",
);

sub set_user_perms {
    my $self = shift;
    my $client = shift;
    my $ses = shift;
    my $maps = shift;

    my $session = $apputils->start_db_session();

    my( $user_obj, $evt ) = $U->checkses($ses);
    return $evt if $evt;
    $apputils->set_audit_info($session, $ses, $user_obj->id, $user_obj->wsid);

    my $perms = $session->request('open-ils.storage.permission.user_perms.atomic', $user_obj->id)->gather(1);

    my $all = undef;
    $all = 1 if ($U->is_true($user_obj->super_user()));
    $all = 1 unless ($U->check_perms($user_obj->id, $user_obj->home_ou, 'EVERYTHING'));

    for my $map (@$maps) {

        my $method = "open-ils.storage.direct.permission.usr_perm_map.update";
        if ($map->isdeleted()) {
            $method = "open-ils.storage.direct.permission.usr_perm_map.delete";
        } elsif ($map->isnew()) {
            $method = "open-ils.storage.direct.permission.usr_perm_map.create";
            $map->clear_id;
        }

        next if (!$all and !grep { $_->perm eq $map->perm and $U->is_true($_->grantable) and $_->depth <= $map->depth } @$perms);
        #warn( "Updating permissions with method $method and session $ses and map $map" );
        $logger->info( "Updating permissions with method $method and map $map" );

        my $stat = $session->request($method, $map)->gather(1);
        $logger->warn( "update failed: ".$U->DB_UPDATE_FAILED($map) ) unless defined($stat);

    }

    $apputils->commit_db_session($session);

    return scalar(@$maps);
}


__PACKAGE__->register_method(
    method  => "user_retrieve_by_barcode",
    authoritative => 1,
    api_name    => "open-ils.actor.user.fleshed.retrieve_by_barcode",);

sub user_retrieve_by_barcode {
    my($self, $client, $auth, $barcode, $flesh_home_ou) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $card = $e->search_actor_card({barcode => $barcode})->[0]
        or return $e->event;

    my $user = flesh_user($card->usr, $e, $flesh_home_ou);
    return $e->event unless $e->allowed(
        "VIEW_USER", $flesh_home_ou ? $user->home_ou->id : $user->home_ou
    );
    return $user;
}



__PACKAGE__->register_method(
    method        => "get_user_by_id",
    authoritative => 1,
    api_name      => "open-ils.actor.user.retrieve",
);

sub get_user_by_id {
    my ($self, $client, $auth, $id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $user = $e->retrieve_actor_user($id) or return $e->event;
    return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);
    return $user;
}


__PACKAGE__->register_method(
    method   => "get_org_types",
    api_name => "open-ils.actor.org_types.retrieve",
);
sub get_org_types {
    return $U->get_org_types();
}


__PACKAGE__->register_method(
    method   => "get_user_ident_types",
    api_name => "open-ils.actor.user.ident_types.retrieve",
);
my $ident_types;
sub get_user_ident_types {
    return $ident_types if $ident_types;
    return $ident_types =
        new_editor()->retrieve_all_config_identification_type();
}


__PACKAGE__->register_method(
    method   => "get_org_unit",
    api_name => "open-ils.actor.org_unit.retrieve",
);

sub get_org_unit {
    my( $self, $client, $user_session, $org_id ) = @_;
    my $e = new_editor(authtoken => $user_session);
    if(!$org_id) {
        return $e->event unless $e->checkauth;
        $org_id = $e->requestor->ws_ou;
    }
    my $o = $e->retrieve_actor_org_unit($org_id)
        or return $e->event;
    return $o;
}

__PACKAGE__->register_method(
    method   => "search_org_unit",
    api_name => "open-ils.actor.org_unit_list.search",
);

sub search_org_unit {

    my( $self, $client, $field, $value ) = @_;

    my $list = OpenILS::Application::AppUtils->simple_scalar_request(
        "open-ils.cstore",
        "open-ils.cstore.direct.actor.org_unit.search.atomic",
        { $field => $value } );

    return $list;
}


# build the org tree

__PACKAGE__->register_method(
    method  => "get_org_tree",
    api_name    => "open-ils.actor.org_tree.retrieve",
    argc        => 0,
    note        => "Returns the entire org tree structure",
);

sub get_org_tree {
    my $self = shift;
    my $client = shift;
    return $U->get_org_tree($client->session->session_locale);
}


__PACKAGE__->register_method(
    method  => "get_org_descendants",
    api_name    => "open-ils.actor.org_tree.descendants.retrieve"
);

# depth is optional.  org_unit is the id
sub get_org_descendants {
    my( $self, $client, $org_unit, $depth ) = @_;

    if(ref $org_unit eq 'ARRAY') {
        $depth ||= [];
        my @trees;
        for my $i (0..scalar(@$org_unit)-1) {
            my $list = $U->simple_scalar_request(
                "open-ils.storage",
                "open-ils.storage.actor.org_unit.descendants.atomic",
                $org_unit->[$i], $depth->[$i] );
            push(@trees, $U->build_org_tree($list));
        }
        return \@trees;

    } else {
        my $orglist = $apputils->simple_scalar_request(
                "open-ils.storage",
                "open-ils.storage.actor.org_unit.descendants.atomic",
                $org_unit, $depth );
        return $U->build_org_tree($orglist);
    }
}


__PACKAGE__->register_method(
    method  => "get_org_ancestors",
    api_name    => "open-ils.actor.org_tree.ancestors.retrieve"
);

# depth is optional.  org_unit is the id
sub get_org_ancestors {
    my( $self, $client, $org_unit, $depth ) = @_;
    my $orglist = $apputils->simple_scalar_request(
            "open-ils.storage",
            "open-ils.storage.actor.org_unit.ancestors.atomic",
            $org_unit, $depth );
    return $U->build_org_tree($orglist);
}


__PACKAGE__->register_method(
    method  => "get_standings",
    api_name    => "open-ils.actor.standings.retrieve"
);

my $user_standings;
sub get_standings {
    return $user_standings if $user_standings;
    return $user_standings =
        $apputils->simple_scalar_request(
            "open-ils.cstore",
            "open-ils.cstore.direct.config.standing.search.atomic",
            { id => { "!=" => undef } }
        );
}


__PACKAGE__->register_method(
    method   => "get_my_org_path",
    api_name => "open-ils.actor.org_unit.full_path.retrieve"
);

sub get_my_org_path {
    my( $self, $client, $auth, $org_id ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $org_id = $e->requestor->ws_ou unless defined $org_id;

    return $apputils->simple_scalar_request(
        "open-ils.storage",
        "open-ils.storage.actor.org_unit.full_path.atomic",
        $org_id );
}

__PACKAGE__->register_method(
    method   => "retrieve_coordinates",
    api_name => "open-ils.actor.geo.retrieve_coordinates",
    signature => {
        params => [
            {desc => 'Authentication token', type => 'string' },
            {type => 'number', desc => 'Context Organizational Unit'},
            {type => 'string', desc => 'Address to look-up as a text string'}
        ],
        return => { desc => 'Hash/object containing latitude and longitude for the provided address.'}
    }
);

sub retrieve_coordinates {
    my( $self, $client, $auth, $org_id, $addr_string ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $org_id = $e->requestor->ws_ou unless defined $org_id;

    return $apputils->simple_scalar_request(
        "open-ils.geo",
        "open-ils.geo.retrieve_coordinates",
        $org_id, $addr_string );
}

__PACKAGE__->register_method(
    method   => "get_my_org_ancestor_at_depth",
    api_name => "open-ils.actor.org_unit.ancestor_at_depth.retrieve"
);

sub get_my_org_ancestor_at_depth {
    my( $self, $client, $auth, $org_id, $depth ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $org_id = $e->requestor->ws_ou unless defined $org_id;

    return $apputils->org_unit_ancestor_at_depth( $org_id, $depth );
}

__PACKAGE__->register_method(
    method   => "patron_adv_search",
    api_name => "open-ils.actor.patron.search.advanced"
);

__PACKAGE__->register_method(
    method   => "patron_adv_search",
    api_name => "open-ils.actor.patron.search.advanced.fleshed",
    stream => 1,
    # Flush the response stream at most 5 patrons in for UI responsiveness.
    max_bundle_count => 5,
    signature => {
        desc => q/Returns a stream of fleshed user objects instead of
            a pile of identifiers/
    }
);

sub patron_adv_search {
    my( $self, $client, $auth, $search_hash, $search_limit,
        $search_sort, $include_inactive, $search_ou, $flesh_fields, $offset) = @_;

    # API params sanity checks.
    # Exit early with empty result if no filter exists.
    # .fleshed call is streaming.  Non-fleshed is effectively atomic.
    my $fleshed = ($self->api_name =~ /fleshed/);
    return ($fleshed ? undef : []) unless (ref $search_hash ||'') eq 'HASH';
    my $search_ok = 0;
    for my $key (keys %$search_hash) {
        next if $search_hash->{$key}{value} =~ /^\s*$/; # empty filter
        $search_ok = 1;
        last;
    }
    return ($fleshed ? undef : []) unless $search_ok;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_USER');

    # depth boundary outside of which patrons must opt-in, default to 0
    my $opt_boundary = 0;
    $opt_boundary = $U->ou_ancestor_setting_value($e->requestor->ws_ou,'org.patron_opt_boundary') if user_opt_in_enabled($self);

    if (not defined $search_ou) {
        my $depth = $U->ou_ancestor_setting_value(
            $e->requestor->ws_ou,
            'circ.patron_edit.duplicate_patron_check_depth'
        );

        if (defined $depth) {
            $search_ou = $U->org_unit_ancestor_at_depth(
                $e->requestor->ws_ou, $depth
            );
        }
    }

    my $ids = $U->storagereq(
        "open-ils.storage.actor.user.crazy_search", $search_hash,
        $search_limit, $search_sort, $include_inactive,
        $e->requestor->ws_ou, $search_ou, $opt_boundary, $offset);

    return $ids unless $self->api_name =~ /fleshed/;

    $client->respond(new_flesh_user($_, $flesh_fields, $e)) for @$ids;

    return;
}


# A migrated (main) password has the form:
# CRYPT( MD5( pw_salt || MD5(real_password) ), pw_salt )
sub modify_migrated_user_password {
    my ($e, $user_id, $passwd) = @_;

    # new password gets a new salt
    my $new_salt = $e->json_query({
        from => ['actor.create_salt', 'main']})->[0];
    $new_salt = $new_salt->{'actor.create_salt'};

    $e->json_query({
        from => [
            'actor.set_passwd',
            $user_id,
            'main',
            md5_hex($new_salt . md5_hex($passwd)),
            $new_salt
        ]
    });
}



__PACKAGE__->register_method(
    method    => "update_passwd",
    api_name  => "open-ils.actor.user.password.update",
    signature => {
        desc   => "Update the operator's password",
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'New password',         type => 'string' },
            { desc => 'Current password',     type => 'string' }
        ],
        return => {desc => '1 on success, Event on error or incorrect current password'}
    }
);

__PACKAGE__->register_method(
    method    => "update_passwd",
    api_name  => "open-ils.actor.user.username.update",
    signature => {
        desc   => "Update the operator's username",
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'New username',         type => 'string' },
            { desc => 'Current password',     type => 'string' }
        ],
        return => {desc => '1 on success, Event on error or incorrect current password'}
    }
);

__PACKAGE__->register_method(
    method    => "update_passwd",
    api_name  => "open-ils.actor.user.email.update",
    signature => {
        desc   => "Update the operator's email address",
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'New email address',    type => 'string' },
            { desc => 'Current password',     type => 'string' }
        ],
        return => {desc => '1 on success, Event on error or incorrect current password'}
    }
);

__PACKAGE__->register_method(
    method    => "update_passwd",
    api_name  => "open-ils.actor.user.locale.update",
    signature => {
        desc   => "Update the operator's i18n locale",
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'New locale',           type => 'string' },
            { desc => 'Current password',     type => 'string' }
        ],
        return => {desc => '1 on success, Event on error or incorrect current password'}
    }
);

__PACKAGE__->register_method(
    method    => "update_passwd",
    api_name  => "open-ils.actor.user.preferred_name.update",
    signature => {
        desc   => "Update the operator's preferred name",
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'User',                 type => 'hash' },
            { desc => 'Current password',     type => 'string' }
        ],
        return => {desc => '1 on success, Event on error or incorrect current password'}
    }
);

sub update_passwd {
    my( $self, $conn, $auth, $new_val, $orig_pw ) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $db_user = $e->retrieve_actor_user($e->requestor->id)
        or return $e->die_event;
    my $api = $self->api_name;

    if (!$U->verify_migrated_user_password($e, $db_user->id, $orig_pw)) {
        $e->rollback;
        return new OpenILS::Event('INCORRECT_PASSWORD');
    }

    my $at_event = 0;
    if( $api =~ /password/o ) {
        # NOTE: with access to the plain text password we could crypt
        # the password without the extra MD5 pre-hashing.  Other changes
        # would be required.  Noting here for future reference.
        modify_migrated_user_password($e, $db_user->id, $new_val);
        $db_user->passwd('');

    } else {

        # if we don't clear the password, the user will be updated with
        # a hashed version of the hashed version of their password
        $db_user->clear_passwd;

        if( $api =~ /username/o ) {

            # make sure no one else has this username
            my $exist = $e->search_actor_user({usrname=>$new_val},{idlist=>1});
            if (@$exist) {
                $e->rollback;
                return new OpenILS::Event('USERNAME_EXISTS');
            }
            $db_user->usrname($new_val);
            $at_event++;

        } elsif( $api =~ /email/o ) {
            $db_user->email($new_val);
            $at_event++;

        } elsif( $api =~ /locale/o ) {
            $db_user->locale($new_val);
            $at_event++;
        } elsif( $api =~ /preferred_name/o ) {
            if(ref($new_val) eq 'HASH'){
                foreach(qw/ pref_prefix pref_first_given_name pref_second_given_name pref_family_name pref_suffix/){
                    $db_user->$_($new_val->{$_});
                    # Set the value to NULL when no data is submitted.
                    eval '$db_user->clear_' . $_ . '();' if($new_val->{$_} eq '' );
                }
                $at_event++;
            }else {
                return new OpenILS::Event('BAD_PARAMS');
            }
        }
    }

    $e->update_actor_user($db_user) or return $e->die_event;
    $e->commit;

    $U->create_events_for_hook('au.updated', $db_user, $e->requestor->ws_ou)
        if $at_event;

    # update the cached user to pick up these changes
    $U->simplereq('open-ils.auth', 'open-ils.auth.session.reset_timeout', $auth, 1);
    return 1;
}



__PACKAGE__->register_method(
    method   => "check_user_perms",
    api_name => "open-ils.actor.user.perm.check",
    notes    => <<"    NOTES");
    Takes a login session, user id, an org id, and an array of perm type strings.  For each
    perm type, if the user does *not* have the given permission it is added
    to a list which is returned from the method.  If all permissions
    are allowed, an empty list is returned
    if the logged in user does not match 'user_id', then the logged in user must
    have VIEW_PERMISSION priveleges.
    NOTES

sub check_user_perms {
    my( $self, $client, $login_session, $user_id, $org_id, $perm_types ) = @_;

    my( $staff, $evt ) = $apputils->checkses($login_session);
    return $evt if $evt;

    if($staff->id ne $user_id) {
        if( $evt = $apputils->check_perms(
            $staff->id, $org_id, 'VIEW_PERMISSION') ) {
            return $evt;
        }
    }

    my @not_allowed;
    for my $perm (@$perm_types) {
        if($apputils->check_perms($user_id, $org_id, $perm)) {
            push @not_allowed, $perm;
        }
    }

    return \@not_allowed
}

__PACKAGE__->register_method(
    method  => "check_user_perms2",
    api_name    => "open-ils.actor.user.perm.check.multi_org",
    notes       => q/
        Checks the permissions on a list of perms and orgs for a user
        @param authtoken The login session key
        @param user_id The id of the user to check
        @param orgs The array of org ids
        @param perms The array of permission names
        @return An array of  [ orgId, permissionName ] arrays that FAILED the check
        if the logged in user does not match 'user_id', then the logged in user must
        have VIEW_PERMISSION priveleges.
    /);

sub check_user_perms2 {
    my( $self, $client, $authtoken, $user_id, $orgs, $perms ) = @_;

    my( $staff, $target, $evt ) = $apputils->checkses_requestor(
        $authtoken, $user_id, 'VIEW_PERMISSION' );
    return $evt if $evt;

    my @not_allowed;
    for my $org (@$orgs) {
        for my $perm (@$perms) {
            if($apputils->check_perms($user_id, $org, $perm)) {
                push @not_allowed, [ $org, $perm ];
            }
        }
    }

    return \@not_allowed
}


__PACKAGE__->register_method(
    method => 'check_user_perms3',
    api_name    => 'open-ils.actor.user.perm.highest_org',
    notes       => q/
        Returns the highest org unit id at which a user has a given permission
        If the requestor does not match the target user, the requestor must have
        'VIEW_PERMISSION' rights at the home org unit of the target user
        @param authtoken The login session key
        @param userid The id of the user in question
        @param perm The permission to check
        @return The org unit highest in the org tree within which the user has
        the requested permission
    /);

sub check_user_perms3 {
    my($self, $client, $authtoken, $user_id, $perm) = @_;
    my $e = new_editor(authtoken=>$authtoken);
    return $e->event unless $e->checkauth;

    my $tree = $U->get_org_tree();

    unless($e->requestor->id == $user_id) {
        my $user = $e->retrieve_actor_user($user_id)
            or return $e->event;
        return $e->event unless $e->allowed('VIEW_PERMISSION', $user->home_ou);
        return $U->find_highest_perm_org($perm, $user_id, $user->home_ou, $tree );
    }

    return $U->find_highest_perm_org($perm, $user_id, $e->requestor->ws_ou, $tree);
}

__PACKAGE__->register_method(
    method => 'user_has_work_perm_at',
    api_name    => 'open-ils.actor.user.has_work_perm_at',
    authoritative => 1,
    signature => {
        desc => q/
            Returns a set of org unit IDs which represent the highest orgs in
            the org tree where the user has the requested permission.  The
            purpose of this method is to return the smallest set of org units
            which represent the full expanse of the user's ability to perform
            the requested action.  The user whose perms this method should
            check is implied by the authtoken. /,
        params => [
            {desc => 'authtoken', type => 'string'},
            {desc => 'permission name', type => 'string'},
            {desc => q/user id, optional.  If present, check perms for
                this user instead of the logged in user/, type => 'number'},
        ],
        return => {desc => 'An array of org IDs'}
    }
);

sub user_has_work_perm_at {
    my($self, $conn, $auth, $perm, $user_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    if(defined $user_id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->event;
        return $e->event unless $e->allowed('VIEW_PERMISSION', $user->home_ou);
    }
    return $U->user_has_work_perm_at($e, $perm, undef, $user_id);
}

__PACKAGE__->register_method(
    method => 'user_has_work_perm_at_batch',
    api_name    => 'open-ils.actor.user.has_work_perm_at.batch',
    authoritative => 1,
);

sub user_has_work_perm_at_batch {
    my($self, $conn, $auth, $perms, $user_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    if(defined $user_id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->event;
        return $e->event unless $e->allowed('VIEW_PERMISSION', $user->home_ou);
    }
    my $map = {};
    $map->{$_} = $U->user_has_work_perm_at($e, $_) for @$perms;
    return $map;
}



__PACKAGE__->register_method(
    method => 'check_user_perms4',
    api_name    => 'open-ils.actor.user.perm.highest_org.batch',
    notes       => q/
        Returns the highest org unit id at which a user has a given permission
        If the requestor does not match the target user, the requestor must have
        'VIEW_PERMISSION' rights at the home org unit of the target user
        @param authtoken The login session key
        @param userid The id of the user in question
        @param perms An array of perm names to check
        @return An array of orgId's  representing the org unit
        highest in the org tree within which the user has the requested permission
        The arrah of orgId's has matches the order of the perms array
    /);

sub check_user_perms4 {
    my( $self, $client, $authtoken, $userid, $perms ) = @_;

    my( $staff, $target, $org, $evt );

    ( $staff, $target, $evt ) = $apputils->checkses_requestor(
        $authtoken, $userid, 'VIEW_PERMISSION' );
    return $evt if $evt;

    my @arr;
    return [] unless ref($perms);
    my $tree = $U->get_org_tree();

    for my $p (@$perms) {
        push( @arr, $U->find_highest_perm_org( $p, $userid, $target->home_ou, $tree ) );
    }
    return \@arr;
}


__PACKAGE__->register_method(
    method        => "user_fines_summary",
    api_name      => "open-ils.actor.user.fines.summary",
    authoritative => 1,
    signature     => {
        desc   => 'Returns a short summary of the users total open fines, '  .
                'excluding voided fines Params are login_session, user_id' ,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'User ID',              type => 'string'}  # number?
        ],
        return => {
            desc => "a 'mous' object, event on error",
        }
    }
);

sub user_fines_summary {
    my( $self, $client, $auth, $user_id ) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    if( $user_id ne $e->requestor->id ) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->event;
        return $e->event unless
            $e->allowed('VIEW_USER_FINES_SUMMARY', $user->home_ou);
    }

    return $e->search_money_open_user_summary({usr => $user_id})->[0];
}


__PACKAGE__->register_method(
    method        => "user_opac_vitals",
    api_name      => "open-ils.actor.user.opac.vital_stats",
    argc          => 1,
    authoritative => 1,
    signature     => {
        desc   => 'Returns a short summary of the users vital stats, including '  .
                'identification information, accumulated balance, number of holds, ' .
                'and current open circulation stats' ,
        params => [
            {desc => 'Authentication token',                          type => 'string'},
            {desc => 'Optional User ID, for use in the staff client', type => 'number'}  # number?
        ],
        return => {
            desc => "An object with four properties: user, fines, checkouts and holds."
        }
    }
);

sub user_opac_vitals {
    my( $self, $client, $auth, $user_id ) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    $user_id ||= $e->requestor->id;

    my $user = $e->retrieve_actor_user( $user_id );

    my ($fines) = $self
        ->method_lookup('open-ils.actor.user.fines.summary')
        ->run($auth => $user_id);
    return $fines if (defined($U->event_code($fines)));

    if (!$fines) {
        $fines = new Fieldmapper::money::open_user_summary ();
        $fines->balance_owed(0.00);
        $fines->total_owed(0.00);
        $fines->total_paid(0.00);
        $fines->usr($user_id);
    }

    my ($holds) = $self
        ->method_lookup('open-ils.actor.user.hold_requests.count')
        ->run($auth => $user_id);
    return $holds if (defined($U->event_code($holds)));

    my ($out) = $self
        ->method_lookup('open-ils.actor.user.checked_out.count')
        ->run($auth => $user_id);
    return $out if (defined($U->event_code($out)));

    $out->{"total_out"} = reduce { $a + $out->{$b} } 0, qw/out overdue/;

    my $unread_msgs = $e->search_actor_usr_message([
        {usr => $user_id, read_date => undef, deleted => 'f',
            'pub' => 't', # this is for the unread message count in the opac
            #'-or' => [ # Hiding Archived messages are for staff UI, not this
            #    {stop_date => undef},
            #    {stop_date => {'>' => 'now'}}
            #],
        },
        {idlist => 1}
    ]);

    return {
        user => {
            first_given_name  => $user->first_given_name,
            second_given_name => $user->second_given_name,
            family_name       => $user->family_name,
            alias             => $user->alias,
            usrname           => $user->usrname
        },
        fines => $fines->to_bare_hash,
        checkouts => $out,
        holds => $holds,
        messages => { unread => scalar(@$unread_msgs) }
    };
}


##### a small consolidation of related method registrations
my $common_params = [
    { desc => 'Authentication token', type => 'string' },
    { desc => 'User ID',              type => 'string' },
    { desc => 'Transactions type (optional, defaults to all)', type => 'string' },
    { desc => 'Options hash.  May contain limit and offset for paged results.', type => 'object' },
];
my %methods = (
    'open-ils.actor.user.transactions'                      => '',
    'open-ils.actor.user.transactions.fleshed'              => '',
    'open-ils.actor.user.transactions.have_charge'          => ' that have an initial charge',
    'open-ils.actor.user.transactions.have_charge.fleshed'  => ' that have an initial charge',
    'open-ils.actor.user.transactions.have_balance'         => ' that have an outstanding balance',
    'open-ils.actor.user.transactions.have_balance.fleshed' => ' that have an outstanding balance',
);

foreach (keys %methods) {
    my %args = (
        method    => "user_transactions",
        api_name  => $_,
        signature => {
            desc   => 'For a given user, retrieve a list of '
                    . (/\.fleshed/ ? 'fleshed ' : '')
                    . 'transactions' . $methods{$_}
                    . ' optionally limited to transactions of a given type.',
            params => $common_params,
            return => {
                desc => "List of objects, or event on error.  Each object is a hash containing: transaction, circ, record. "
                    . 'These represent the relevant (mbts) transaction, attached circulation and title pointed to in the circ, respectively.',
            }
        }
    );
    $args{authoritative} = 1;
    __PACKAGE__->register_method(%args);
}

# Now for the counts
%methods = (
    'open-ils.actor.user.transactions.count'              => '',
    'open-ils.actor.user.transactions.have_charge.count'  => ' that have an initial charge',
    'open-ils.actor.user.transactions.have_balance.count' => ' that have an outstanding balance',
);

foreach (keys %methods) {
    my %args = (
        method    => "user_transactions",
        api_name  => $_,
        signature => {
            desc   => 'For a given user, retrieve a count of open '
                    . 'transactions' . $methods{$_}
                    . ' optionally limited to transactions of a given type.',
            params => $common_params,
            return => { desc => "Integer count of transactions, or event on error" }
        }
    );
    /\.have_balance/ and $args{authoritative} = 1;     # FIXME: I don't know why have_charge isn't authoritative
    __PACKAGE__->register_method(%args);
}

__PACKAGE__->register_method(
    method        => "user_transactions",
    api_name      => "open-ils.actor.user.transactions.have_balance.total",
    authoritative => 1,
    signature     => {
        desc   => 'For a given user, retrieve the total balance owed for open transactions,'
                . ' optionally limited to transactions of a given type.',
        params => $common_params,
        return => { desc => "Decimal balance value, or event on error" }
    }
);


sub user_transactions {
    my( $self, $client, $auth, $user_id, $type, $options ) = @_;
    $options ||= {};

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $user = $e->retrieve_actor_user($user_id) or return $e->event;

    return $e->event unless
        $e->requestor->id == $user_id or
        $e->allowed('VIEW_USER_TRANSACTIONS', $user->home_ou);

    my $api = $self->api_name();

    my $filter = ($api =~ /have_balance/o) ?
        { 'balance_owed' => { '<>' => 0 } }:
        { 'total_owed' => { '>' => 0 } };

    my $method = 'open-ils.actor.user.transactions.history.still_open';
    $method = "$method.authoritative" if $api =~ /authoritative/;
    my ($trans) = $self->method_lookup($method)->run($auth, $user_id, $type, $filter, $options);

    if($api =~ /total/o) {
        my $total = 0.0;
        $total += $_->balance_owed for @$trans;
        return $total;
    }

    ($api =~ /count/o  ) and return scalar @$trans;
    ($api !~ /fleshed/o) and return $trans;

    my @resp;
    for my $t (@$trans) {

        if( $t->xact_type ne 'circulation' ) {
            push @resp, {transaction => $t};
            next;
        }

        my $circ_data = flesh_circ($e, $t->id);
        push @resp, {transaction => $t, %$circ_data};
    }

    return \@resp;
}


__PACKAGE__->register_method(
    method   => "user_transaction_retrieve",
    api_name => "open-ils.actor.user.transaction.fleshed.retrieve",
    argc     => 1,
    authoritative => 1,
    notes    => "Returns a fleshed transaction record"
);

__PACKAGE__->register_method(
    method   => "user_transaction_retrieve",
    api_name => "open-ils.actor.user.transaction.retrieve",
    argc     => 1,
    authoritative => 1,
    notes    => "Returns a transaction record"
);

sub user_transaction_retrieve {
    my($self, $client, $auth, $bill_id) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $trans = $e->retrieve_money_billable_transaction_summary(
        [$bill_id, {flesh => 1, flesh_fields => {mbts => ['usr']}}]) or return $e->event;

    return $e->event unless $e->allowed('VIEW_USER_TRANSACTIONS', $trans->usr->home_ou);

    $trans->usr($trans->usr->id); # de-flesh for backwards compat

    return $trans unless $self->api_name =~ /flesh/;
    return {transaction => $trans} if $trans->xact_type ne 'circulation';

    my $circ_data = flesh_circ($e, $trans->id, 1);

    return {transaction => $trans, %$circ_data};
}

sub flesh_circ {
    my $e = shift;
    my $circ_id = shift;
    my $flesh_copy = shift;

    my $circ = $e->retrieve_action_circulation([
        $circ_id, {
            flesh => 3,
            flesh_fields => {
                circ => ['target_copy'],
                acp => ['call_number'],
                acn => ['record']
            }
        }
    ]);

    my $mods;
    my $copy = $circ->target_copy;

    if($circ->target_copy->call_number->id == OILS_PRECAT_CALL_NUMBER) {
        $mods = new Fieldmapper::metabib::virtual_record;
        $mods->doc_id(OILS_PRECAT_RECORD);
        $mods->title($copy->dummy_title);
        $mods->author($copy->dummy_author);

    } else {
        $mods = $U->record_to_mvr($circ->target_copy->call_number->record);
    }

    # more de-fleshiing
    $circ->target_copy($circ->target_copy->id);
    $copy->call_number($copy->call_number->id);

    return {circ => $circ, record => $mods, copy => ($flesh_copy) ? $copy : undef };
}


__PACKAGE__->register_method(
    method        => "hold_request_count",
    api_name      => "open-ils.actor.user.hold_requests.count",
    authoritative => 1,
    argc          => 1,
    notes         => q/
        Returns hold ready vs. total counts.
        If a context org unit is provided, a third value
        is returned with key 'behind_desk', which reports
        how many holds are ready at the pickup library
        with the behind_desk flag set to true.
    /
);

sub hold_request_count {
    my( $self, $client, $authtoken, $user_id, $ctx_org ) = @_;
    my $e = new_editor(authtoken => $authtoken);
    return $e->event unless $e->checkauth;

    $user_id = $e->requestor->id unless defined $user_id;

    if($e->requestor->id ne $user_id) {
        my $user = $e->retrieve_actor_user($user_id);
        return $e->event unless $e->allowed('VIEW_HOLD', $user->home_ou);
    }

    my $holds = $e->json_query({
        select => {ahr => ['pickup_lib', 'current_shelf_lib', 'behind_desk']},
        from => 'ahr',
        where => {
            usr => $user_id,
            fulfillment_time => {"=" => undef },
            cancel_time => undef,
        }
    });

    my @ready = grep {
        $_->{current_shelf_lib} and # avoid undef warnings
        $_->{pickup_lib} eq $_->{current_shelf_lib}
    } @$holds;

    my $resp = {
        total => scalar(@$holds),
        ready => int(scalar(@ready))
    };

    if ($ctx_org) {
        # count of holds ready at pickup lib with behind_desk true.
        $resp->{behind_desk} = int(scalar(
            grep {
                $_->{pickup_lib} == $ctx_org and
                $U->is_true($_->{behind_desk})
            } @ready
        ));
    }

    return $resp;
}

__PACKAGE__->register_method(
    method        => "checked_out",
    api_name      => "open-ils.actor.user.checked_out",
    authoritative => 1,
    argc          => 2,
    signature     => {
        desc => "For a given user, returns a structure of circulations objects sorted by out, overdue, lost, claims_returned, long_overdue. "
            . "A list of IDs are returned of each type.  Circs marked lost, long_overdue, and claims_returned will not be 'finished' "
            . "(i.e., outstanding balance or some other pending action on the circ). "
            . "The .count method also includes a 'total' field which sums all open circs.",
        params => [
            { desc => 'Authentication Token', type => 'string'},
            { desc => 'User ID',              type => 'string'},
        ],
        return => {
            desc => 'Returns event on error, or an object with ID lists, like: '
                . '{"out":[12552,451232], "claims_returned":[], "long_overdue":[23421] "overdue":[], "lost":[]}'
        },
    }
);

__PACKAGE__->register_method(
    method        => "checked_out",
    api_name      => "open-ils.actor.user.checked_out.count",
    authoritative => 1,
    argc          => 2,
    signature     => q/@see open-ils.actor.user.checked_out/
);

sub checked_out {
    my( $self, $conn, $auth, $userid ) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    if( $userid ne $e->requestor->id ) {
        my $user = $e->retrieve_actor_user($userid) or return $e->event;
        unless($e->allowed('VIEW_CIRCULATIONS', $user->home_ou)) {

            # see if there is a friend link allowing circ.view perms
            my $allowed = OpenILS::Application::Actor::Friends->friend_perm_allowed(
                $e, $userid, $e->requestor->id, 'circ.view');
            return $e->event unless $allowed;
        }
    }

    my $count = $self->api_name =~ /count/;
    return _checked_out( $count, $e, $userid );
}

sub _checked_out {
    my( $iscount, $e, $userid ) = @_;

    my %result = (
        out => [],
        overdue => [],
        lost => [],
        claims_returned => [],
        long_overdue => []
    );
    my $meth = 'retrieve_action_open_circ_';

    if ($iscount) {
        $meth .= 'count';
        %result = (
            out => 0,
            overdue => 0,
            lost => 0,
            claims_returned => 0,
            long_overdue => 0
        );
    } else {
        $meth .= 'list';
    }

    my $data = $e->$meth($userid);

    if ($data) {
        if ($iscount) {
            $result{$_} += $data->$_() for (keys %result);
            $result{total} += $data->$_() for (keys %result);
        } else {
            for my $k (keys %result) {
                $result{$k} = [ grep { $_ > 0 } split( ',', $data->$k()) ];
            }
        }
    }

    return \%result;
}



__PACKAGE__->register_method(
    method        => "checked_in_with_fines",
    api_name      => "open-ils.actor.user.checked_in_with_fines",
    authoritative => 1,
    argc          => 2,
    signature     => q/@see open-ils.actor.user.checked_out/
);

sub checked_in_with_fines {
    my( $self, $conn, $auth, $userid ) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    if( $userid ne $e->requestor->id ) {
        return $e->event unless $e->allowed('VIEW_CIRCULATIONS');
    }

    # money is owed on these items and they are checked in
    my $open = $e->search_action_circulation(
        {
            usr             => $userid,
            xact_finish     => undef,
            checkin_time    => { "!=" => undef },
        }
    );


    my( @lost, @cr, @lo );
    for my $c (@$open) {
        push( @lost, $c->id ) if ($c->stop_fines eq 'LOST');
        push( @cr, $c->id ) if $c->stop_fines eq 'CLAIMSRETURNED';
        push( @lo, $c->id ) if $c->stop_fines eq 'LONGOVERDUE';
    }

    return {
        lost        => \@lost,
        claims_returned => \@cr,
        long_overdue        => \@lo
    };
}


sub _sigmaker {
    my ($api, $desc, $auth) = @_;
    $desc = $desc ? (" " . $desc) : '';
    my $ids = ($api =~ /ids$/) ? 1 : 0;
    my @sig = (
        argc      => 1,
        method    => "user_transaction_history",
        api_name  => "open-ils.actor.user.transactions.$api",
        signature => {
            desc   => "For a given User ID, returns a list of billable transaction" .
                    ($ids ? " id" : '') .
                    "s$desc, optionally filtered by type and/or fields in money.billable_xact_summary.  " .
                    "The VIEW_USER_TRANSACTIONS permission is required to view another user's transactions",
            params => [
                {desc => 'Authentication token',        type => 'string'},
                {desc => 'User ID',                     type => 'number'},
                {desc => 'Transaction type (optional)', type => 'number'},
                {desc => 'Hash of Billable Transaction Summary filters (optional)', type => 'object'}
            ],
            return => {
                desc => 'List of transaction' . ($ids ? " id" : '') . 's, Event on error'
            },
        }
    );
    $auth and push @sig, (authoritative => 1);
    return @sig;
}

my %auth_hist_methods = (
    'history'             => '',
    'history.have_charge' => 'that have an initial charge',
    'history.still_open'  => 'that are not finished',
    'history.have_balance'         => 'that have a balance',
    'history.have_bill'            => 'that have billings',
    'history.have_bill_or_payment' => 'that have non-zero-sum billings or at least 1 payment',
    'history.have_payment' => 'that have at least 1 payment',
);

foreach (keys %auth_hist_methods) {
    __PACKAGE__->register_method(_sigmaker($_,       $auth_hist_methods{$_}, 1));
    __PACKAGE__->register_method(_sigmaker("$_.ids", $auth_hist_methods{$_}, 1));
    __PACKAGE__->register_method(_sigmaker("$_.fleshed", $auth_hist_methods{$_}, 1));
}

sub user_transaction_history {
    my( $self, $conn, $auth, $userid, $type, $filter, $options ) = @_;
    $filter ||= {};
    $options ||= {};

    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    if ($e->requestor->id ne $userid) {
        return $e->die_event unless $e->allowed('VIEW_USER_TRANSACTIONS');
    }

    my $api = $self->api_name;
    my @xact_finish  = (xact_finish => undef ) if ($api =~ /history\.still_open$/);     # What about history.still_open.ids?

    if(defined($type)) {
        $filter->{'xact_type'} = $type;
    }

    if($api =~ /have_bill_or_payment/o) {

        # transactions that have a non-zero sum across all billings or at least 1 payment
        $filter->{'-or'} = {
            'balance_owed' => { '<>' => 0 },
            'last_payment_ts' => { '<>' => undef }
        };

    } elsif($api =~ /have_payment/) {

        $filter->{last_payment_ts} ||= {'<>' => undef};

    } elsif( $api =~ /have_balance/o) {

        # transactions that have a non-zero overall balance
        $filter->{'balance_owed'} = { '<>' => 0 };

    } elsif( $api =~ /have_charge/o) {

        # transactions that have at least 1 billing, regardless of whether it was voided
        $filter->{'last_billing_ts'} = { '<>' => undef };

    } elsif( $api =~ /have_bill/o) {    # needs to be an elsif, or we double-match have_bill_or_payment!

        # transactions that have non-zero sum across all billings.  This will exclude
        # xacts where all billings have been voided
        $filter->{'total_owed'} = { '<>' => 0 };
    }

    my $options_clause = { order_by => { mbt => 'xact_start '.($$options{sort} ? uc($$options{sort}) : 'DESC') } };
    $options_clause->{'limit'} = $options->{'limit'} if $options->{'limit'};
    $options_clause->{'offset'} = $options->{'offset'} if $options->{'offset'};

    my $mbts = $e->search_money_billable_transaction_summary(
        [   { usr => $userid, @xact_finish, %$filter },
            $options_clause
        ]
    );

    return [map {$_->id} @$mbts] if $api =~ /\.ids/;
    return $mbts unless $api =~ /fleshed/;

    my @resp;
    for my $t (@$mbts) {

        if( $t->xact_type ne 'circulation' ) {
            push @resp, {transaction => $t};
            next;
        }

        my $circ_data = flesh_circ($e, $t->id);
        push @resp, {transaction => $t, %$circ_data};
    }

    return \@resp;
}



__PACKAGE__->register_method(
    method   => "user_perms",
    api_name => "open-ils.actor.permissions.user_perms.retrieve",
    argc     => 1,
    notes    => "Returns a list of permissions"
);

sub user_perms {
    my( $self, $client, $authtoken, $user ) = @_;

    my( $staff, $evt ) = $apputils->checkses($authtoken);
    return $evt if $evt;

    $user ||= $staff->id;

    if( $user != $staff->id and $evt = $apputils->check_perms( $staff->id, $staff->home_ou, 'VIEW_PERMISSION') ) {
        return $evt;
    }

    return $apputils->simple_scalar_request(
        "open-ils.storage",
        "open-ils.storage.permission.user_perms.atomic",
        $user);
}

__PACKAGE__->register_method(
    method   => "retrieve_perms",
    api_name => "open-ils.actor.permissions.retrieve",
    notes    => "Returns a list of permissions"
);
sub retrieve_perms {
    my( $self, $client ) = @_;
    return $apputils->simple_scalar_request(
        "open-ils.cstore",
        "open-ils.cstore.direct.permission.perm_list.search.atomic",
        { id => { '!=' => undef } }
    );
}

__PACKAGE__->register_method(
    method   => "retrieve_groups",
    api_name => "open-ils.actor.groups.retrieve",
    notes    => "Returns a list of user groups"
);
sub retrieve_groups {
    my( $self, $client ) = @_;
    return new_editor()->retrieve_all_permission_grp_tree();
}

__PACKAGE__->register_method(
    method  => "retrieve_org_address",
    api_name    => "open-ils.actor.org_unit.address.retrieve",
    notes        => <<'    NOTES');
    Returns an org_unit address by ID
    @param An org_address ID
    NOTES
sub retrieve_org_address {
    my( $self, $client, $id ) = @_;
    return $apputils->simple_scalar_request(
        "open-ils.cstore",
        "open-ils.cstore.direct.actor.org_address.retrieve",
        $id
    );
}

__PACKAGE__->register_method(
    method   => "retrieve_groups_tree",
    api_name => "open-ils.actor.groups.tree.retrieve",
    notes    => "Returns a list of user groups"
);

sub retrieve_groups_tree {
    my( $self, $client ) = @_;
    return new_editor()->search_permission_grp_tree(
        [
            { parent => undef},
            {
                flesh               => -1,
                flesh_fields    => { pgt => ["children"] },
                order_by            => { pgt => 'name'}
            }
        ]
    )->[0];
}


__PACKAGE__->register_method(
    method   => "add_user_to_groups",
    api_name => "open-ils.actor.user.set_groups",
    notes    => "Adds a user to one or more permission groups"
);

sub add_user_to_groups {
    my( $self, $client, $authtoken, $userid, $groups ) = @_;

    my( $requestor, $target, $evt ) = $apputils->checkses_requestor(
        $authtoken, $userid, 'CREATE_USER_GROUP_LINK' );
    return $evt if $evt;

    ( $requestor, $target, $evt ) = $apputils->checkses_requestor(
        $authtoken, $userid, 'REMOVE_USER_GROUP_LINK' );
    return $evt if $evt;

    $apputils->simplereq(
        'open-ils.storage',
        'open-ils.storage.direct.permission.usr_grp_map.mass_delete', { usr => $userid } );

    for my $group (@$groups) {
        my $link = Fieldmapper::permission::usr_grp_map->new;
        $link->grp($group);
        $link->usr($userid);

        my $id = $apputils->simplereq(
            'open-ils.storage',
            'open-ils.storage.direct.permission.usr_grp_map.create', $link );
    }

    return 1;
}

__PACKAGE__->register_method(
    method   => "get_user_perm_groups",
    api_name => "open-ils.actor.user.get_groups",
    notes    => "Retrieve a user's permission groups."
);


sub get_user_perm_groups {
    my( $self, $client, $authtoken, $userid ) = @_;

    my( $requestor, $target, $evt ) = $apputils->checkses_requestor(
        $authtoken, $userid, 'VIEW_PERM_GROUPS' );
    return $evt if $evt;

    return $apputils->simplereq(
        'open-ils.cstore',
        'open-ils.cstore.direct.permission.usr_grp_map.search.atomic', { usr => $userid } );
}


__PACKAGE__->register_method(
    method   => "get_user_work_ous",
    api_name => "open-ils.actor.user.get_work_ous",
    notes    => "Retrieve a user's work org units."
);

__PACKAGE__->register_method(
    method   => "get_user_work_ous",
    api_name => "open-ils.actor.user.get_work_ous.ids",
    notes    => "Retrieve a user's work org units."
);

sub get_user_work_ous {
    my( $self, $client, $auth, $userid ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $userid ||= $e->requestor->id;

    if($e->requestor->id != $userid) {
        my $user = $e->retrieve_actor_user($userid)
            or return $e->event;
        return $e->event unless $e->allowed('ASSIGN_WORK_ORG_UNIT', $user->home_ou);
    }

    return $e->search_permission_usr_work_ou_map({usr => $userid})
        unless $self->api_name =~ /.ids$/;

    # client just wants a list of org IDs
    return $U->get_user_work_ou_ids($e, $userid);
}



__PACKAGE__->register_method(
    method    => 'register_workstation',
    api_name  => 'open-ils.actor.workstation.register.override',
    signature => q/@see open-ils.actor.workstation.register/
);

__PACKAGE__->register_method(
    method    => 'register_workstation',
    api_name  => 'open-ils.actor.workstation.register',
    signature => q/
        Registers a new workstion in the system
        @param authtoken The login session key
        @param name The name of the workstation id
        @param owner The org unit that owns this workstation
        @return The workstation id on success, WORKSTATION_NAME_EXISTS
        if the name is already in use.
    /
);

sub register_workstation {
    my( $self, $conn, $authtoken, $name, $owner, $oargs ) = @_;

    my $e = new_editor(authtoken=>$authtoken, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('REGISTER_WORKSTATION', $owner);
    my $existing = $e->search_actor_workstation({name => $name})->[0];
    $oargs = { all => 1 } unless defined $oargs;

    if( $existing ) {

        if( $self->api_name =~ /override/o && ($oargs->{all} || grep { $_ eq 'WORKSTATION_NAME_EXISTS' } @{$oargs->{events}}) ) {
            # workstation with the given name exists.

            if($owner ne $existing->owning_lib) {
                # if necessary, update the owning_lib of the workstation

                $logger->info("changing owning lib of workstation ".$existing->id.
                    " from ".$existing->owning_lib." to $owner");
                return $e->die_event unless
                    $e->allowed('UPDATE_WORKSTATION', $existing->owning_lib);

                return $e->die_event unless $e->allowed('UPDATE_WORKSTATION', $owner);

                $existing->owning_lib($owner);
                return $e->die_event unless $e->update_actor_workstation($existing);

                $e->commit;

            } else {
                $logger->info(
                    "attempt to register an existing workstation.  returning existing ID");
            }

            return $existing->id;

        } else {
            return OpenILS::Event->new('WORKSTATION_NAME_EXISTS')
        }
    }

    my $ws = Fieldmapper::actor::workstation->new;
    $ws->owning_lib($owner);
    $ws->name($name);
    $e->create_actor_workstation($ws) or return $e->die_event;
    $e->commit;
    return $ws->id; # note: editor sets the id on the new object for us
}

__PACKAGE__->register_method(
    method    => 'workstation_list',
    api_name  => 'open-ils.actor.workstation.list',
    signature => q/
        Returns a list of workstations registered at the given location
        @param authtoken The login session key
        @param ids A list of org_unit.id's for the workstation owners
    /
);

sub workstation_list {
    my( $self, $conn, $authtoken, @orgs ) = @_;

    my $e = new_editor(authtoken=>$authtoken);
    return $e->event unless $e->checkauth;
    my %results;

    for my $o (@orgs) {
        return $e->event
            unless $e->allowed('REGISTER_WORKSTATION', $o);
        $results{$o} = $e->search_actor_workstation({owning_lib=>$o});
    }
    return \%results;
}

__PACKAGE__->register_method(
    method        => 'fetch_patron_messages',
    api_name      => 'open-ils.actor.message.retrieve',
    authoritative => 1,
    signature     => q/
        Returns a list of notes for a given user, not
        including ones marked deleted
        @param authtoken The login session key
        @param patronid patron ID
        @param options hash containing optional limit and offset
    /
);

sub fetch_patron_messages {
    my( $self, $conn, $auth, $patronid, $options ) = @_;

    $options ||= {};

    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    if ($e->requestor->id ne $patronid) {
        return $e->die_event unless $e->allowed('VIEW_USER');
    }

    my $select_clause = { usr => $patronid };
    my $options_clause = { order_by => { aum => 'create_date DESC' } };
    $options_clause->{'limit'} = $options->{'limit'} if $options->{'limit'};
    $options_clause->{'offset'} = $options->{'offset'} if $options->{'offset'};

    my $aum = $e->search_actor_usr_message([ $select_clause, $options_clause ]);
    return $aum;
}


__PACKAGE__->register_method(
    method    => 'usrname_exists',
    api_name  => 'open-ils.actor.username.exists',
    signature => {
        desc  => 'Check if a username is already taken (by an undeleted patron)',
        param => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Username',             type => 'string'}
        ],
        return => {
            desc => 'id of existing user if username exists, undef otherwise.  Event on error'
        },
    }
);

sub usrname_exists {
    my( $self, $conn, $auth, $usrname ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $a = $e->search_actor_user({usrname => $usrname}, {idlist=>1});
    return $$a[0] if $a and @$a;
    return undef;
}

__PACKAGE__->register_method(
    method        => 'barcode_exists',
    api_name      => 'open-ils.actor.barcode.exists',
    authoritative => 1,
    signature     => 'Returns 1 if the requested barcode exists, returns 0 otherwise'
);

sub barcode_exists {
    my( $self, $conn, $auth, $barcode ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $card = $e->search_actor_card({barcode => $barcode});
    if (@$card) {
        return 1;
    } else {
        return 0;
    }
    #return undef unless @$card;
    #return $card->[0]->usr;
}


__PACKAGE__->register_method(
    method   => 'retrieve_net_levels',
    api_name => 'open-ils.actor.net_access_level.retrieve.all',
);

sub retrieve_net_levels {
    my( $self, $conn, $auth ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->retrieve_all_config_net_access_level();
}

# Retain the old typo API name just in case
__PACKAGE__->register_method(
    method   => 'fetch_org_by_shortname',
    api_name => 'open-ils.actor.org_unit.retrieve_by_shorname',
);
__PACKAGE__->register_method(
    method   => 'fetch_org_by_shortname',
    api_name => 'open-ils.actor.org_unit.retrieve_by_shortname',
);
sub fetch_org_by_shortname {
    my( $self, $conn, $sname ) = @_;
    my $e = new_editor();
    my $org = $e->search_actor_org_unit({ shortname => uc($sname)})->[0];
    return $e->event unless $org;
    return $org;
}


__PACKAGE__->register_method(
    method   => 'session_home_lib',
    api_name => 'open-ils.actor.session.home_lib',
);

sub session_home_lib {
    my( $self, $conn, $auth ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return undef unless $e->checkauth;
    my $org = $e->retrieve_actor_org_unit($e->requestor->home_ou);
    return $org->shortname;
}

__PACKAGE__->register_method(
    method    => 'session_safe_token',
    api_name  => 'open-ils.actor.session.safe_token',
    signature => q/
        Returns a hashed session ID that is safe for export to the world.
        This safe token will expire after 1 hour of non-use.
        @param auth Active authentication token
    /
);

sub session_safe_token {
    my( $self, $conn, $auth ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return undef unless $e->checkauth;

    my $safe_token = md5_hex($auth);

    $cache ||= OpenSRF::Utils::Cache->new("global", 0);

    # add more user fields as needed
    $cache->put_cache(
        "safe-token-user-$safe_token", {
            id => $e->requestor->id,
            home_ou_shortname => $e->retrieve_actor_org_unit(
                $e->requestor->home_ou)->shortname,
        },
        60 * 60
    );

    return $safe_token;
}


__PACKAGE__->register_method(
    method    => 'safe_token_home_lib',
    api_name  => 'open-ils.actor.safe_token.home_lib.shortname',
    signature => q/
        Returns the home library shortname from the session
        asscociated with a safe token from generated by
        open-ils.actor.session.safe_token.
        @param safe_token Active safe token
        @param who Optional user activity "ewho" value
    /
);

sub safe_token_home_lib {
    my( $self, $conn, $safe_token, $who ) = @_;
    $cache ||= OpenSRF::Utils::Cache->new("global", 0);

    my $blob = $cache->get_cache("safe-token-user-$safe_token");
    return unless $blob;

    $U->log_user_activity($blob->{id}, $who, 'verify');
    return $blob->{home_ou_shortname};
}


__PACKAGE__->register_method(
    method   => "update_penalties",
    api_name => "open-ils.actor.user.penalties.update"
);

__PACKAGE__->register_method(
    method   => "update_penalties",
    api_name => "open-ils.actor.user.penalties.update_at_home"
);

sub update_penalties {
    my($self, $conn, $auth, $user_id, @penalties) = @_;
    my $e = new_editor(authtoken=>$auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);
    my $context_org = ($self->api_name =~ /_at_home$/) ? $user->home_ou : $e->requestor->ws_ou;
    my $evt = OpenILS::Utils::Penalty->calculate_penalties($e, $user_id, $context_org, @penalties);
    return $evt if $evt;
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
    method   => "apply_note",
    api_name => "open-ils.actor.user.penalty.apply"
);

__PACKAGE__->register_method(
    method   => "apply_note",
    api_name => "open-ils.actor.user.note.apply"
);

sub apply_note {
    my($self, $conn, $auth, $penalty, $msg) = @_;

    $msg ||= {};

    my $e = new_editor(authtoken=>$auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $user = $e->retrieve_actor_user($penalty->usr) or return $e->die_event;
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

    my $ptype = $e->retrieve_config_standing_penalty($penalty->standing_penalty) or return $e->die_event;

    my $ctx_org = $penalty->org_unit; # csp org_depth is now considered in the UI for the org drop-down menu

    if (($msg->{title} || $msg->{message}) && ($msg->{title} ne '' || $msg->{message} ne '')) {
        my $aum = Fieldmapper::actor::usr_message->new;

        $aum->create_date('now');
        $aum->sending_lib($e->requestor->ws_ou);
        $aum->title($msg->{title});
        $aum->usr($penalty->usr);
        $aum->message($msg->{message});
        $aum->pub($msg->{pub});

        $aum = $e->create_actor_usr_message($aum)
            or return $e->die_event;

        $penalty->usr_message($aum->id);
    }

    $penalty->org_unit($ctx_org);
    $penalty->staff($e->requestor->id);
    $e->create_actor_user_standing_penalty($penalty) or return $e->die_event;

    $e->commit;
    return $penalty->id;
}

__PACKAGE__->register_method(
    method   => "modify_penalty",
    api_name => "open-ils.actor.user.penalty.modify"
);

__PACKAGE__->register_method(
    method   => "modify_penalty",
    api_name => "open-ils.actor.user.note.modify"
);

sub modify_penalty {
    my($self, $conn, $auth, $penalty, $usr_msg) = @_;

    my $e = new_editor(authtoken=>$auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $user = $e->retrieve_actor_user($penalty->usr) or return $e->die_event;
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

    $usr_msg->editor($e->requestor->id);
    $usr_msg->edit_date('now');

    if ($usr_msg->isnew) {
        $usr_msg = $e->create_actor_usr_message($usr_msg)
            or return $e->die_event;
        $penalty->usr_message($usr_msg->id);
    } else {
        $usr_msg = $e->update_actor_usr_message($usr_msg)
            or return $e->die_event;
    }

    if ($penalty->isnew) {
        $penalty = $e->create_actor_user_standing_penalty($penalty)
            or return $e->die_event;
    } else {
        $penalty = $e->update_actor_user_standing_penalty($penalty)
            or return $e->die_event;
    }

    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method   => "remove_penalty",
    api_name => "open-ils.actor.user.penalty.remove"
);

__PACKAGE__->register_method(
    method   => "remove_penalty",
    api_name => "open-ils.actor.user.note.remove"
);

sub remove_penalty {
    my($self, $conn, $auth, $penalty) = @_;
    my $e = new_editor(authtoken=>$auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    my $user = $e->retrieve_actor_user($penalty->usr) or return $e->die_event;
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

    $e->delete_actor_user_standing_penalty($penalty) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method   => "update_penalty_note",
    api_name => "open-ils.actor.user.note.note.update"
);

sub update_penalty_note {
    my($self, $conn, $auth, $penalty_ids, $note) = @_;
    my $e = new_editor(authtoken=>$auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    for my $penalty_id (@$penalty_ids) {
        my $penalty = $e->search_actor_user_standing_penalty([
            { id => $penalty_id },
            {   flesh => 1,
                flesh_fields => {aum => ['usr_message']}
            }
        ])->[0];
        if (! $penalty ) { return $e->die_event; }
        my $user = $e->retrieve_actor_user($penalty->usr) or return $e->die_event;
        return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

        my $aum = $penalty->usr_message();
        if (!$aum) {
            $aum = Fieldmapper::actor::usr_message->new;

            $aum->create_date('now');
            $aum->sending_lib($e->requestor->ws_ou);
            $aum->title('');
            $aum->usr($penalty->usr);
            $aum->message($note);
            $aum->pub(0);
            $aum->isnew(1);

            $aum = $e->create_actor_usr_message($aum)
                or return $e->die_event;

            $penalty->usr_message($aum->id);
            $penalty->ischanged(1);
            $e->update_actor_user_standing_penalty($penalty) or return $e->die_event;
        } else {
            $aum = $e->retrieve_actor_usr_message($aum) or return $e->die_event;
            $aum->message($note); $aum->ischanged(1);
            $e->update_actor_usr_message($aum) or return $e->die_event;
        }
    }
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method   => "ranged_penalty_thresholds",
    api_name => "open-ils.actor.grp_penalty_threshold.ranged.retrieve",
    stream   => 1
);

sub ranged_penalty_thresholds {
    my($self, $conn, $auth, $context_org) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_GROUP_PENALTY_THRESHOLD', $context_org);
    my $list = $e->search_permission_grp_penalty_threshold([
        {org_unit => $U->get_org_ancestors($context_org)},
        {order_by => {pgpt => 'id'}}
    ]);
    $conn->respond($_) for @$list;
    return undef;
}



__PACKAGE__->register_method(
    method        => "user_retrieve_fleshed_by_id",
    authoritative => 1,
    api_name      => "open-ils.actor.user.fleshed.retrieve",
);

sub user_retrieve_fleshed_by_id {
    my( $self, $client, $auth, $user_id, $fields ) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    if( $e->requestor->id != $user_id ) {
        return $e->event unless $e->allowed('VIEW_USER');
    }

    $fields ||= [
        "cards",
        "card",
        "groups",
        "standing_penalties",
        "settings",
        "addresses",
        "billing_address",
        "mailing_address",
        "stat_cat_entries",
        "waiver_entries",
        "usr_activity" ];
    return new_flesh_user($user_id, $fields, $e);
}


sub new_flesh_user {

    my $id = shift;
    my $fields = shift || [];
    my $e = shift;

    my $fetch_penalties = 0;
    if(grep {$_ eq 'standing_penalties'} @$fields) {
        $fields = [grep {$_ ne 'standing_penalties'} @$fields];
        $fetch_penalties = 1;
    }

    my $fetch_notes = 0;
    if(grep {$_ eq 'notes'} @$fields) {
        $fields = [grep {$_ ne 'notes'} @$fields];
        $fetch_notes = 1;
    }

    my $fetch_usr_act = 0;
    if(grep {$_ eq 'usr_activity'} @$fields) {
        $fields = [grep {$_ ne 'usr_activity'} @$fields];
        $fetch_usr_act = 1;
    }

    my $user = $e->retrieve_actor_user(
    [
        $id,
        {
            "flesh"             => 1,
            "flesh_fields" =>  { "au" => $fields }
        }
    ]
    ) or return $e->die_event;


    if( grep { $_ eq 'addresses' } @$fields ) {

        $user->addresses([]) unless @{$user->addresses};
        # don't expose "replaced" addresses by default
        $user->addresses([grep {$_->id >= 0} @{$user->addresses}]);

        if( ref $user->billing_address ) {
            unless( grep { $user->billing_address->id == $_->id } @{$user->addresses} ) {
                push( @{$user->addresses}, $user->billing_address );
            }
        }

        if( ref $user->mailing_address ) {
            unless( grep { $user->mailing_address->id == $_->id } @{$user->addresses} ) {
                push( @{$user->addresses}, $user->mailing_address );
            }
        }
    }

    if($fetch_penalties) {
        # grab the user penalties ranged for this location
        $user->standing_penalties(
            $e->search_actor_user_standing_penalty([
                {   usr => $id,
                    '-or' => [
                        {stop_date => undef},
                        {stop_date => {'>' => 'now'}}
                    ],
                    org_unit => $U->get_org_full_path($e->requestor->ws_ou)
                },
                {   flesh => 1,
                    flesh_fields => {ausp => ['standing_penalty','usr_message']}
                }
            ])
        );
    }

    if($fetch_notes) {
        # grab notes (now actor.usr_message_penalty) that have not hit their stop_date
        # NOTE: This is a view that already filters out deleted messages that are not
        # attached to a penalty
        $user->notes([
            @{ $e->search_actor_usr_message_penalty([
                {   usr => $id,
                    '-or' => [
                        {stop_date => undef},
                        {stop_date => {'>' => 'now'}}
                    ],
                }, {}
            ]) }
        ]);
    }

    # retrieve the most recent usr_activity entry
    if ($fetch_usr_act) {

        # max number to return for simple patron fleshing
        my $limit = $U->ou_ancestor_setting_value(
            $e->requestor->ws_ou,
            'circ.patron.usr_activity_retrieve.max');

        my $opts = {
            flesh => 1,
            flesh_fields => {auact => ['etype']},
            order_by => {auact => 'event_time DESC'},
        };

        # 0 == none, <0 == return all
        $limit = 1 unless defined $limit;
        $opts->{limit} = $limit if $limit > 0;

        $user->usr_activity(
            ($limit == 0) ?
                [] : # skip the DB call
                $e->search_actor_usr_activity([{usr => $user->id}, $opts])
        );
    }

    $e->rollback;
    $user->clear_passwd();
    return $user;
}




__PACKAGE__->register_method(
    method   => "user_retrieve_parts",
    api_name => "open-ils.actor.user.retrieve.parts",
);

sub user_retrieve_parts {
    my( $self, $client, $auth, $user_id, $fields ) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    $user_id ||= $e->requestor->id;
    if( $e->requestor->id != $user_id ) {
        return $e->event unless $e->allowed('VIEW_USER');
    }
    my @resp;
    my $user = $e->retrieve_actor_user($user_id) or return $e->event;
    push(@resp, $user->$_()) for(@$fields);
    return \@resp;
}



__PACKAGE__->register_method(
    method    => 'user_opt_in_enabled',
    api_name  => 'open-ils.actor.user.org_unit_opt_in.enabled',
    signature => '@return 1 if user opt-in is globally enabled, 0 otherwise.'
);

sub user_opt_in_enabled {
    my($self, $conn) = @_;
    my $sc = OpenSRF::Utils::SettingsClient->new;
    return 1 if lc($sc->config_value(share => user => 'opt_in')) eq 'true';
    return 0;
}


__PACKAGE__->register_method(
    method    => 'user_opt_in_at_org',
    api_name  => 'open-ils.actor.user.org_unit_opt_in.check',
    signature => q/
        @param $auth The auth token
        @param user_id The ID of the user to test
        @return 1 if the user has opted in at the specified org,
            2 if opt-in is disallowed for the user's home org,
            event on error, and 0 otherwise. /
);
sub user_opt_in_at_org {
    my($self, $conn, $auth, $user_id) = @_;

    # see if we even need to enforce the opt-in value
    return 1 unless user_opt_in_enabled($self);

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $user = $e->retrieve_actor_user($user_id) or return $e->event;
    return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);

    my $ws_org = $e->requestor->ws_ou;
    # user is automatically opted-in if they are from the local org
    return 1 if $user->home_ou eq $ws_org;

    # get the boundary setting
    my $opt_boundary = $U->ou_ancestor_setting_value($e->requestor->ws_ou,'org.patron_opt_boundary');

    # auto opt in if user falls within the opt boundary
    my $opt_orgs = $U->get_org_descendants($ws_org, $opt_boundary);

    return 1 if grep $_ eq $user->home_ou, @$opt_orgs;

    # check whether opt-in is restricted at the user's home library
    my $opt_restrict_depth = $U->ou_ancestor_setting_value($user->home_ou, 'org.restrict_opt_to_depth');
    if ($opt_restrict_depth) {
        my $restrict_ancestor = $U->org_unit_ancestor_at_depth($user->home_ou, $opt_restrict_depth);
        my $unrestricted_orgs = $U->get_org_descendants($restrict_ancestor);

        # opt-in is disallowed unless the workstation org is within the home
        # library's opt-in scope
        return 2 unless grep $_ eq $e->requestor->ws_ou, @$unrestricted_orgs;
    }

    my $vals = $e->search_actor_usr_org_unit_opt_in(
        {org_unit=>$opt_orgs, usr=>$user_id},{idlist=>1});

    return 1 if @$vals;
    return 0;
}

__PACKAGE__->register_method(
    method    => 'create_user_opt_in_at_org',
    api_name  => 'open-ils.actor.user.org_unit_opt_in.create',
    signature => q/
        @param $auth The auth token
        @param user_id The ID of the user to test
        @return The ID of the newly created object, event on error./
);

sub create_user_opt_in_at_org {
    my($self, $conn, $auth, $user_id, $org_id) = @_;

    my $e = new_editor(authtoken => $auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    # if a specific org unit wasn't passed in, get one based on the defaults;
    if(!$org_id){
        my $wsou = $e->requestor->ws_ou;
        # get the default opt depth
        my $opt_depth = $U->ou_ancestor_setting_value($wsou,'org.patron_opt_default');
        # get the org unit at that depth
        my $org = $e->json_query({
            from => [ 'actor.org_unit_ancestor_at_depth', $wsou, $opt_depth ]})->[0];
        $org_id = $org->{id};
    }
    if (!$org_id) {
        # fall back to the workstation OU, the pre-opt-in-boundary way
        $org_id = $e->requestor->ws_ou;
    }

    my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

    my $opt_in = Fieldmapper::actor::usr_org_unit_opt_in->new;

    $opt_in->org_unit($org_id);
    $opt_in->usr($user_id);
    $opt_in->staff($e->requestor->id);
    $opt_in->opt_in_ts('now');
    $opt_in->opt_in_ws($e->requestor->wsid);

    $opt_in = $e->create_actor_usr_org_unit_opt_in($opt_in)
        or return $e->die_event;

    $e->commit;

    return $opt_in->id;
}


__PACKAGE__->register_method (
    method      => 'retrieve_org_hours',
    api_name    => 'open-ils.actor.org_unit.hours_of_operation.retrieve',
    signature   => q/
        Returns the hours of operation for a specified org unit
        @param authtoken The login session key
        @param org_id The org_unit ID
    /
);

sub retrieve_org_hours {
    my($self, $conn, $auth, $org_id) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    $org_id ||= $e->requestor->ws_ou;
    return $e->retrieve_actor_org_unit_hours_of_operation($org_id);
}


__PACKAGE__->register_method (
    method      => 'verify_user_password',
    api_name    => 'open-ils.actor.verify_user_password',
    signature   => q/
        Given a barcode or username and the MD5 encoded password,
        The password can also be passed without the MD5 hashing.
        returns 1 if the password is correct.  Returns 0 otherwise.
    /
);

sub verify_user_password {
    my($self, $conn, $auth, $barcode, $username, $password, $pass_nohash) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    my $user;
    my $user_by_barcode;
    my $user_by_username;
    if($barcode) {
        my $card = $e->search_actor_card([
            {barcode => $barcode},
            {flesh => 1, flesh_fields => {ac => ['usr']}}])->[0] or return 0;
        $user_by_barcode = $card->usr;
        $user = $user_by_barcode;
    }
    if ($username) {
        $user_by_username = $e->search_actor_user({usrname => $username})->[0] or return 0;
        $user = $user_by_username;
    }
    return 0 if (!$user || $U->is_true($user->deleted));
    return 0 if ($user_by_username && $user_by_barcode && $user_by_username->id != $user_by_barcode->id);
    return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);

    if ($pass_nohash) {
        return $U->verify_migrated_user_password($e, $user->id, $pass_nohash);
    } else {
        return $U->verify_migrated_user_password($e, $user->id, $password, 1);
    }
}

__PACKAGE__->register_method (
    method      => 'retrieve_usr_id_via_barcode_or_usrname',
    api_name    => "open-ils.actor.user.retrieve_id_by_barcode_or_username",
    signature   => q/
        Given a barcode or username returns the id for the user or
        a failure event.
    /
);

sub retrieve_usr_id_via_barcode_or_usrname {
    my($self, $conn, $auth, $barcode, $username) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    my $id_as_barcode= OpenSRF::Utils::SettingsClient->new->config_value(apps => 'open-ils.actor' => app_settings => 'id_as_barcode');
    my $user;
    my $user_by_barcode;
    my $user_by_username;
    $logger->info("$id_as_barcode is the ID as BARCODE");
    if($barcode) {
        my $card = $e->search_actor_card([
            {barcode => $barcode},
            {flesh => 1, flesh_fields => {ac => ['usr']}}])->[0];
        if ($id_as_barcode =~ /^t/i) {
            if (!$card) {
                $user = $e->retrieve_actor_user($barcode);
                return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' ) if(!$user);
            }else {
                $user_by_barcode = $card->usr;
                $user = $user_by_barcode;
            }
        }else {
            return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' ) if(!$card);
            $user_by_barcode = $card->usr;
            $user = $user_by_barcode;
        }
    }

    if ($username) {
        $user_by_username = $e->search_actor_user({usrname => $username})->[0] or return OpenILS::Event->new( 'ACTOR_USR_NOT_FOUND' );

        $user = $user_by_username;
    }
    return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' ) if (!$user);
    return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' ) if ($user_by_username && $user_by_barcode && $user_by_username->id != $user_by_barcode->id);
    return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);
    return $user->id;
}


__PACKAGE__->register_method (
    method      => 'merge_users',
    api_name    => 'open-ils.actor.user.merge',
    signature   => {
        desc => q/
            Given a list of source users and destination user, transfer all data from the source
            to the dest user and delete the source user.  All user related data is
            transferred, including circulations, holds, bookbags, etc.
        /
    }
);

sub merge_users {
    my($self, $conn, $auth, $master_id, $user_ids, $options) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    # disallow the merge if any subordinate accounts are in collections
    my $colls = $e->search_money_collections_tracker({usr => $user_ids}, {idlist => 1});
    return OpenILS::Event->new('MERGED_USER_IN_COLLECTIONS', payload => $user_ids) if @$colls;

    return OpenILS::Event->new('MERGE_SELF_NOT_ALLOWED')
        if $master_id == $e->requestor->id;

    my $master_user = $e->retrieve_actor_user($master_id) or return $e->die_event;
    my $evt = group_perm_failed($e, $e->requestor, $master_user);
    return $evt if $evt;

    my $del_addrs = ($U->ou_ancestor_setting_value(
        $master_user->home_ou, 'circ.user_merge.delete_addresses', $e)) ? 't' : 'f';
    my $del_cards = ($U->ou_ancestor_setting_value(
        $master_user->home_ou, 'circ.user_merge.delete_cards', $e)) ? 't' : 'f';
    my $deactivate_cards = ($U->ou_ancestor_setting_value(
        $master_user->home_ou, 'circ.user_merge.deactivate_cards', $e)) ? 't' : 'f';

    for my $src_id (@$user_ids) {

        my $src_user = $e->retrieve_actor_user($src_id) or return $e->die_event;
        my $evt = group_perm_failed($e, $e->requestor, $src_user);
        return $evt if $evt;

        return OpenILS::Event->new('MERGE_SELF_NOT_ALLOWED')
            if $src_id == $e->requestor->id;

        return $e->die_event unless $e->allowed('MERGE_USERS', $src_user->home_ou);
        if($src_user->home_ou ne $master_user->home_ou) {
            return $e->die_event unless $e->allowed('MERGE_USERS', $master_user->home_ou);
        }

        return $e->die_event unless
            $e->json_query({from => [
                'actor.usr_merge',
                $src_id,
                $master_id,
                $del_addrs,
                $del_cards,
                $deactivate_cards
            ]});
    }

    $e->commit;
    return 1;
}


__PACKAGE__->register_method (
    method      => 'approve_user_address',
    api_name    => 'open-ils.actor.user.pending_address.approve',
    signature   => {
        desc => q/
        /
    }
);

sub approve_user_address {
    my($self, $conn, $auth, $addr) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    if(ref $addr) {
        # if the caller passes an address object, assume they want to
        # update it first before approving it
        $e->update_actor_user_address($addr) or return $e->die_event;
    } else {
        $addr = $e->retrieve_actor_user_address($addr) or return $e->die_event;
    }
    my $user = $e->retrieve_actor_user($addr->usr);
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);
    my $result = $e->json_query({from => ['actor.approve_pending_address', $addr->id]})->[0]
        or return $e->die_event;
    $e->commit;
    return [values %$result]->[0];
}


__PACKAGE__->register_method (
    method      => 'retrieve_friends',
    api_name    => 'open-ils.actor.friends.retrieve',
    signature   => {
        desc => q/
            returns { confirmed: [], pending_out: [], pending_in: []}
            pending_out are users I'm requesting friendship with
            pending_in are users requesting friendship with me
        /
    }
);

sub retrieve_friends {
    my($self, $conn, $auth, $user_id, $options) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    $user_id ||= $e->requestor->id;

    if($user_id != $e->requestor->id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->event;
        return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);
    }

    return OpenILS::Application::Actor::Friends->retrieve_friends(
        $e, $user_id, $options);
}



__PACKAGE__->register_method (
    method      => 'apply_friend_perms',
    api_name    => 'open-ils.actor.friends.perms.apply',
    signature   => {
        desc => q/
        /
    }
);
sub apply_friend_perms {
    my($self, $conn, $auth, $user_id, $delegate_id, @perms) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    if($user_id != $e->requestor->id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;
        return $e->die_event unless $e->allowed('VIEW_USER', $user->home_ou);
    }

    for my $perm (@perms) {
        my $evt =
            OpenILS::Application::Actor::Friends->apply_friend_perm(
                $e, $user_id, $delegate_id, $perm);
        return $evt if $evt;
    }

    $e->commit;
    return 1;
}


__PACKAGE__->register_method (
    method      => 'update_user_pending_address',
    api_name    => 'open-ils.actor.user.address.pending.cud'
);

sub update_user_pending_address {
    my($self, $conn, $auth, $addr) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $user = $e->retrieve_actor_user($addr->usr) or return $e->die_event;
    if($addr->usr != $e->requestor->id) {
        return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);
    }

    if($addr->isnew) {
        $e->create_actor_user_address($addr) or return $e->die_event;
    } elsif($addr->isdeleted) {
        $e->delete_actor_user_address($addr) or return $e->die_event;
    } else {
        $e->update_actor_user_address($addr) or return $e->die_event;
    }

    $e->commit;
    $U->create_events_for_hook('au.updated', $user, $e->requestor->ws_ou);

    return $addr->id;
}


__PACKAGE__->register_method (
    method      => 'user_events',
    api_name    => 'open-ils.actor.user.events.circ',
    stream      => 1,
);
__PACKAGE__->register_method (
    method      => 'user_events',
    api_name    => 'open-ils.actor.user.events.ahr',
    stream      => 1,
);

sub user_events {
    my($self, $conn, $auth, $user_id, $filters) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    (my $obj_type = $self->api_name) =~ s/.*\.([a-z]+)$/$1/;
    my $user_field = 'usr';

    $filters ||= {};
    $filters->{target} = {
        select => { $obj_type => ['id'] },
        from => $obj_type,
        where => {usr => $user_id}
    };

    my $user = $e->retrieve_actor_user($user_id) or return $e->event;
    if($e->requestor->id != $user_id) {
        return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);
    }

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    my $req = $ses->request('open-ils.trigger.events_by_target',
        $obj_type, $filters, {atevdef => ['reactor', 'validator']}, 2);

    while(my $resp = $req->recv) {
        my $val = $resp->content;
        my $tgt = $val->target;

        if($obj_type eq 'circ') {
            $tgt->target_copy($e->retrieve_asset_copy($tgt->target_copy));

        } elsif($obj_type eq 'ahr') {
            $tgt->current_copy($e->retrieve_asset_copy($tgt->current_copy))
                if $tgt->current_copy;
        }

        $conn->respond($val) if $val;
    }

    return undef;
}

__PACKAGE__->register_method (
    method      => 'copy_events',
    api_name    => 'open-ils.actor.copy.events.circ',
    stream      => 1,
);
__PACKAGE__->register_method (
    method      => 'copy_events',
    api_name    => 'open-ils.actor.copy.events.ahr',
    stream      => 1,
);

sub copy_events {
    my($self, $conn, $auth, $copy_id, $filters) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    (my $obj_type = $self->api_name) =~ s/.*\.([a-z]+)$/$1/;

    my $copy = $e->retrieve_asset_copy($copy_id) or return $e->event;

    my $copy_field = 'target_copy';
    $copy_field = 'current_copy' if $obj_type eq 'ahr';

    $filters ||= {};
    $filters->{target} = {
        select => { $obj_type => ['id'] },
        from => $obj_type,
        where => {$copy_field => $copy_id}
    };


    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    my $req = $ses->request('open-ils.trigger.events_by_target',
        $obj_type, $filters, {atevdef => ['reactor', 'validator']}, 2);

    while(my $resp = $req->recv) {
        my $val = $resp->content;
        my $tgt = $val->target;

        my $user = $e->retrieve_actor_user($tgt->usr);
        if($e->requestor->id != $user->id) {
            return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);
        }

        $tgt->$copy_field($copy);

        $tgt->usr($user);
        $conn->respond($val) if $val;
    }

    return undef;
}


__PACKAGE__->register_method (
    method      => 'get_itemsout_notices',
    api_name    => 'open-ils.actor.user.itemsout.notices',
    stream      => 1,
    argc        => 2,
    signature   => {
        desc => q/Summary counts of circulat notices/,
        params => [
            {desc => 'authtoken', type => 'string'},
            {desc => 'circulation identifiers', type => 'array of numbers'}
        ],
        return => q/Stream of summary objects/
    }
);

sub get_itemsout_notices {
    my ($self, $client, $auth, $circ_ids) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    $circ_ids = [$circ_ids] unless ref $circ_ids eq 'ARRAY';

    for my $circ_id (@$circ_ids) {
        my $resp = get_itemsout_notices_impl($e, $circ_id);

        if ($U->is_event($resp)) {
            $client->respond($resp);
            return;
        }

        $client->respond({circ_id => $circ_id, %$resp});
    }

    return undef;
}



sub get_itemsout_notices_impl {
    my ($e, $circId) = @_;

    my $requestorId = $e->requestor->id;

    my $circ = $e->retrieve_action_circulation($circId) or return $e->event;

    my $patronId = $circ->usr;

    if( $patronId ne $requestorId ){
        my $user = $e->retrieve_actor_user($requestorId) or return $e->event;
        return $e->event unless $e->allowed('VIEW_CIRCULATIONS', $user->home_ou);
    }

    #my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    #my $req = $ses->request('open-ils.trigger.events_by_target',
    #	'circ', {target => [$circId], event=> {state=>'complete'}});
    # ^ Above removed in favor of faster json_query.
    #
    # SQL:
    # select complete_time
    # from action_trigger.event atev
    #     JOIN action_trigger.event_definition def ON (def.id = atev.event_def)
    #     JOIN action_trigger.hook athook ON (athook.key = def.hook)
    # where hook = 'checkout.due' AND state = 'complete' and target = <circId>;
    #

    my $ctx_loc = $e->requestor->ws_ou;
    my $exclude_courtesy_notices = $U->ou_ancestor_setting_value(
        $ctx_loc, 'webstaff.circ.itemsout_notice_count_excludes_courtesies');

    my $query = {
	    select => { atev => ["complete_time"] },
	    from => {
		    atev => {
			    atevdef => { field => "id",fkey => "event_def"}
		    }
	    },
	    where => {
            "+atevdef" => { active => 't', hook => 'checkout.due' },
            "+atev" => { target => $circId, state => 'complete' }
        }
    };

    if ($exclude_courtesy_notices){
        $query->{"where"}->{"+atevdef"}->{validator} = { "<>" => "CircIsOpen"};
    }

    my %resblob = ( numNotices => 0, lastDt => undef );

    my $res = $e->json_query($query);
    for my $ndate (@$res) {
	$resblob{numNotices}++;
	if( !defined $resblob{lastDt}){
	    $resblob{lastDt} = $$ndate{complete_time};
        }

	if ($resblob{lastDt} lt $$ndate{complete_time}){
	   $resblob{lastDt} = $$ndate{complete_time};
	}
   }

    return \%resblob;
}

__PACKAGE__->register_method (
    method      => 'update_events',
    api_name    => 'open-ils.actor.user.event.cancel.batch',
    stream      => 1,
);
__PACKAGE__->register_method (
    method      => 'update_events',
    api_name    => 'open-ils.actor.user.event.reset.batch',
    stream      => 1,
);

sub update_events {
    my($self, $conn, $auth, $event_ids) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    my $x = 1;
    for my $id (@$event_ids) {

        # do a little dance to determine what user we are ultimately affecting
        my $event = $e->retrieve_action_trigger_event([
            $id,
            {   flesh => 2,
                flesh_fields => {atev => ['event_def'], atevdef => ['hook']}
            }
        ]) or return $e->die_event;

        my $user_id;
        if($event->event_def->hook->core_type eq 'circ') {
            $user_id = $e->retrieve_action_circulation($event->target)->usr;
        } elsif($event->event_def->hook->core_type eq 'ahr') {
            $user_id = $e->retrieve_action_hold_request($event->target)->usr;
        } else {
            return 0;
        }

        my $user = $e->retrieve_actor_user($user_id);
        return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

        if($self->api_name =~ /cancel/) {
            $event->state('invalid');
        } elsif($self->api_name =~ /reset/) {
            $event->clear_start_time;
            $event->clear_update_time;
            $event->state('pending');
        }

        $e->update_action_trigger_event($event) or return $e->die_event;
        $conn->respond({maximum => scalar(@$event_ids), progress => $x++});
    }

    $e->commit;
    return {complete => 1};
}


__PACKAGE__->register_method (
    method      => 'really_delete_user',
    api_name    => 'open-ils.actor.user.delete.override',
    signature   => q/@see open-ils.actor.user.delete/
);

__PACKAGE__->register_method (
    method      => 'really_delete_user',
    api_name    => 'open-ils.actor.user.delete',
    signature   => q/
        It anonymizes all personally identifiable information in actor.usr. By calling actor.usr_purge_data()
        it also purges related data from other tables, sometimes by transferring it to a designated destination user.
        The usrname field (along with first_given_name and family_name) is updated to id '-PURGED-' now().
        dest_usr_id is only required when deleting a user that performs staff functions.
    /
);

sub really_delete_user {
    my($self, $conn, $auth, $user_id, $dest_user_id, $oargs) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    $oargs = { all => 1 } unless defined $oargs;

    # Find all unclosed billings for for user $user_id, thereby, also checking for open circs
    my $open_bills = $e->json_query({
        select => { mbts => ['id'] },
        from => 'mbts',
        where => {
            xact_finish => { '=' => undef },
            usr => { '=' => $user_id },
        }
    }) or return $e->die_event;

    my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;

    # No deleting patrons with open billings or checked out copies, unless perm-enabled override
    if (@$open_bills) {
        return $e->die_event(OpenILS::Event->new('ACTOR_USER_DELETE_OPEN_XACTS'))
        unless $self->api_name =~ /override/o && ($oargs->{all} || grep { $_ eq 'ACTOR_USER_DELETE_OPEN_XACTS' } @{$oargs->{events}})
        && $e->allowed('ACTOR_USER_DELETE_OPEN_XACTS.override', $user->home_ou);
    }
    # No deleting yourself - UI is supposed to stop you first, though.
    return $e->die_event unless $e->requestor->id != $user->id;
    return $e->die_event unless $e->allowed('DELETE_USER', $user->home_ou);
    # Check if you are allowed to mess with this patron permission group at all
    my $evt = group_perm_failed($e, $e->requestor, $user);
    return $e->die_event($evt) if $evt;
    my $stat = $e->json_query(
        {from => ['actor.usr_delete', $user_id, $dest_user_id]})->[0]
        or return $e->die_event;
    $e->commit;
    return 1;
}


__PACKAGE__->register_method (
    method      => 'user_payments',
    api_name    => 'open-ils.actor.user.payments.retrieve',
    stream => 1,
    signature   => q/
        Returns all payments for a given user.  Default order is newest payments first.
        @param auth Authentication token
        @param user_id The user ID
        @param filters An optional hash of filters, including limit, offset, and order_by definitions
    /
);

sub user_payments {
    my($self, $conn, $auth, $user_id, $filters) = @_;
    $filters ||= {};

    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    my $user = $e->retrieve_actor_user($user_id) or return $e->event;
    return $e->event unless
        $e->requestor->id == $user_id or
        $e->allowed('VIEW_USER_TRANSACTIONS', $user->home_ou);

    # Find all payments for all transactions for user $user_id
    my $query = {
        select => {mp => ['id']},
        from => 'mp',
        where => {
            xact => {
                in => {
                    select => {mbt => ['id']},
                    from => 'mbt',
                    where => {usr => $user_id}
                }
            }
        },
        order_by => [
            { # by default, order newest payments first
                class => 'mp',
                field => 'payment_ts',
                direction => 'desc'
            }, {
                # secondary sort in ID as a tie-breaker, since payments created
                # within the same transaction will have identical payment_ts's
                class => 'mp',
                field => 'id'
            }
        ]
    };

    for (qw/order_by limit offset/) {
        $query->{$_} = $filters->{$_} if defined $filters->{$_};
    }

    if(defined $filters->{where}) {
        foreach (keys %{$filters->{where}}) {
            # don't allow the caller to expand the result set to other users
            $query->{where}->{$_} = $filters->{where}->{$_} unless $_ eq 'xact';
        }
    }

    my $payment_ids = $e->json_query($query);
    for my $pid (@$payment_ids) {
        my $pay = $e->retrieve_money_payment([
            $pid->{id},
            {   flesh => 6,
                flesh_fields => {
                    mp => ['xact'],
                    mbt => ['summary', 'circulation', 'grocery'],
                    circ => ['target_copy'],
                    acp => ['call_number'],
                    acn => ['record']
                }
            }
        ]);

        my $resp = {
            mp => $pay,
            xact_type => $pay->xact->summary->xact_type,
            last_billing_type => $pay->xact->summary->last_billing_type,
        };

        if($pay->xact->summary->xact_type eq 'circulation') {
            $resp->{barcode} = $pay->xact->circulation->target_copy->barcode;
            $resp->{title} = $U->record_to_mvr($pay->xact->circulation->target_copy->call_number->record)->title;
        }

        $pay->xact($pay->xact->id); # de-flesh
        $conn->respond($resp);
    }

    return undef;
}



__PACKAGE__->register_method (
    method      => 'negative_balance_users',
    api_name    => 'open-ils.actor.users.negative_balance',
    stream => 1,
    signature   => q/
        Returns all users that have an overall negative balance
        @param auth Authentication token
        @param org_id The context org unit as an ID or list of IDs.  This will be the home
        library of the user.  If no org_unit is specified, no org unit filter is applied
    /
);

sub negative_balance_users {
    my($self, $conn, $auth, $org_id, $options) = @_;

    $options ||= {};
    $options->{limit} = 1000 unless $options->{limit};
    $options->{offset} = 0 unless $options->{offset};

    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('VIEW_USER', $org_id);

    my $query = {
        select => {
            mous => ['usr', 'balance_owed'],
            au => ['home_ou'],
            mbts => [
                {column => 'last_billing_ts', transform => 'max', aggregate => 1},
                {column => 'last_payment_ts', transform => 'max', aggregate => 1},
            ]
        },
        from => {
            mous => {
                au => {
                    fkey => 'usr',
                    field => 'id',
                    join => {
                        mbts => {
                            key => 'id',
                            field => 'usr'
                        }
                    }
                }
            }
        },
        where => {'+mous' => {balance_owed => {'<' => 0}}, '+au' => {deleted => 'f'}},
        offset => $options->{offset},
        limit => $options->{limit},
        order_by => [{class => 'mous', field => 'usr'}]
    };

    $org_id = $U->get_org_descendants($org_id) if $options->{org_descendants};

    $query->{from}->{mous}->{au}->{filter}->{home_ou} = $org_id if $org_id;

    my $list = $e->json_query($query, {timeout => 600});

    for my $data (@$list) {
        $conn->respond({
            usr => $e->retrieve_actor_user([$data->{usr}, {flesh => 1, flesh_fields => {au => ['card']}}]),
            balance_owed => $data->{balance_owed},
            last_billing_activity => max($data->{last_billing_ts}, $data->{last_payment_ts})
        });
    }

    return undef;
}

__PACKAGE__->register_method(
    method  => "request_password_reset",
    api_name    => "open-ils.actor.patron.password_reset.request",
    signature   => {
        desc => "Generates a UUID token usable with the open-ils.actor.patron.password_reset.commit " .
                "method for changing a user's password.  The UUID token is distributed via A/T "      .
                "templates (i.e. email to the user).",
        params => [
            { desc => 'user_id_type', type => 'string' },
            { desc => 'user_id', type => 'string' },
            { desc => 'optional (based on library setting) matching email address for authorizing request', type => 'string' },
        ],
        return => {desc => '1 on success, Event on error'}
    }
);
sub request_password_reset {
    my($self, $conn, $user_id_type, $user_id, $email) = @_;

    # Check to see if password reset requests are already being throttled:
    # 0. Check cache to see if we're in throttle mode (avoid hitting database)

    my $e = new_editor(xact => 1);
    my $user;

    # Get the user, if any, depending on the input value
    if ($user_id_type eq 'username') {
        $user = $e->search_actor_user({usrname => $user_id})->[0];
        if (!$user) {
            $e->die_event;
            return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' );
        }
    } elsif ($user_id_type eq 'barcode') {
        my $card = $e->search_actor_card([
            {barcode => $user_id},
            {flesh => 1, flesh_fields => {ac => ['usr']}}])->[0];
        if (!$card) {
            $e->die_event;
            return OpenILS::Event->new('ACTOR_USER_NOT_FOUND');
        }
        $user = $card->usr;
    }

    # If the user doesn't have an email address, we can't help them
    if (!$user->email) {
        $e->die_event;
        return OpenILS::Event->new('PATRON_NO_EMAIL_ADDRESS');
    }

    my $email_must_match = $U->ou_ancestor_setting_value($user->home_ou, 'circ.password_reset_request_requires_matching_email');
    if ($email_must_match) {
        if (lc($user->email) ne lc($email)) {
            return OpenILS::Event->new('EMAIL_VERIFICATION_FAILED');
        }
    }

    _reset_password_request($conn, $e, $user);
}

# Once we have the user, we can issue the password reset request
# XXX Add a wrapper method that accepts barcode + email input
sub _reset_password_request {
    my ($conn, $e, $user) = @_;

    # 1. Get throttle threshold and time-to-live from OU_settings
    my $aupr_throttle = $U->ou_ancestor_setting_value($user->home_ou, 'circ.password_reset_request_throttle') || 1000;
    my $aupr_ttl = $U->ou_ancestor_setting_value($user->home_ou, 'circ.password_reset_request_time_to_live') || 24*60*60;

    my $threshold_time = DateTime->now(time_zone => 'local')->subtract(seconds => $aupr_ttl)->iso8601();

    # 2. Get time of last request and number of active requests (num_active)
    my $active_requests = $e->json_query({
        from => 'aupr',
        select => {
            aupr => [
                {
                    column => 'uuid',
                    transform => 'COUNT'
                },
                {
                    column => 'request_time',
                    transform => 'MAX'
                }
            ]
        },
        where => {
            has_been_reset => { '=' => 'f' },
            request_time => { '>' => $threshold_time }
        }
    });

    # Guard against no active requests
    if ($active_requests->[0]->{'request_time'}) {
        my $last_request = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($active_requests->[0]->{'request_time'}));
        my $now = DateTime::Format::ISO8601->new();

        # 3. if (num_active > throttle_threshold) and (now - last_request < 1 minute)
        if (($active_requests->[0]->{'usr'} > $aupr_throttle) &&
            ($last_request->add_duration('1 minute') > $now)) {
            $cache->put_cache('open-ils.actor.password.throttle', DateTime::Format::ISO8601->new(), 60);
            $e->die_event;
            return OpenILS::Event->new('PATRON_TOO_MANY_ACTIVE_PASSWORD_RESET_REQUESTS');
        }
    }

    # TODO Check to see if the user is in a password-reset-restricted group

    # Otherwise, go ahead and try to get the user.

    # Check the number of active requests for this user
    $active_requests = $e->json_query({
        from => 'aupr',
        select => {
            aupr => [
                {
                    column => 'usr',
                    transform => 'COUNT'
                }
            ]
        },
        where => {
            usr => { '=' => $user->id },
            has_been_reset => { '=' => 'f' },
            request_time => { '>' => $threshold_time }
        }
    });

    $logger->info("User " . $user->id . " has " . $active_requests->[0]->{'usr'} . " active password reset requests.");

    # if less than or equal to per-user threshold, proceed; otherwise, return event
    my $aupr_per_user_limit = $U->ou_ancestor_setting_value($user->home_ou, 'circ.password_reset_request_per_user_limit') || 3;
    if ($active_requests->[0]->{'usr'} > $aupr_per_user_limit) {
        $e->die_event;
        return OpenILS::Event->new('PATRON_TOO_MANY_ACTIVE_PASSWORD_RESET_REQUESTS');
    }

    # Create the aupr object and insert into the database
    my $reset_request = Fieldmapper::actor::usr_password_reset->new;
    my $uuid = create_uuid_as_string(UUID_V4);
    $reset_request->uuid($uuid);
    $reset_request->usr($user->id);

    my $aupr = $e->create_actor_usr_password_reset($reset_request) or return $e->die_event;
    $e->commit;

    # Create an event to notify user of the URL to reset their password

    # Can we stuff this in the user_data param for trigger autocreate?
    my $hostname = $U->ou_ancestor_setting_value($user->home_ou, 'lib.hostname') || 'localhost';

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    $ses->request('open-ils.trigger.event.autocreate', 'password.reset_request', $aupr, $user->home_ou);

    # Trunk only
    # $U->create_trigger_event('password.reset_request', $aupr, $user->home_ou);

    return 1;
}

__PACKAGE__->register_method(
    method  => "commit_password_reset",
    api_name    => "open-ils.actor.patron.password_reset.commit",
    signature   => {
        desc => "Checks a UUID token generated by the open-ils.actor.patron.password_reset.request method for " .
                "validity, and if valid, uses it as authorization for changing the associated user's password " .
                "with the supplied password.",
        params => [
            { desc => 'uuid', type => 'string' },
            { desc => 'password', type => 'string' },
        ],
        return => {desc => '1 on success, Event on error'}
    }
);
sub commit_password_reset {
    my($self, $conn, $uuid, $password) = @_;

    # Check to see if password reset requests are already being throttled:
    # 0. Check cache to see if we're in throttle mode (avoid hitting database)
    $cache ||= OpenSRF::Utils::Cache->new("global", 0);
    my $throttle = $cache->get_cache('open-ils.actor.password.throttle') || undef;
    if ($throttle) {
        return OpenILS::Event->new('PATRON_NOT_AN_ACTIVE_PASSWORD_RESET_REQUEST');
    }

    my $e = new_editor(xact => 1);

    my $aupr = $e->search_actor_usr_password_reset({
        uuid => $uuid,
        has_been_reset => 0
    });

    if (!$aupr->[0]) {
        $e->die_event;
        return OpenILS::Event->new('PATRON_NOT_AN_ACTIVE_PASSWORD_RESET_REQUEST');
    }
    my $user_id = $aupr->[0]->usr;
    my $user = $e->retrieve_actor_user($user_id);

    # Ensure we're still within the TTL for the request
    my $aupr_ttl = $U->ou_ancestor_setting_value($user->home_ou, 'circ.password_reset_request_time_to_live') || 24*60*60;
    my $threshold = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($aupr->[0]->request_time))->add(seconds => $aupr_ttl);
    if ($threshold < DateTime->now(time_zone => 'local')) {
        $e->die_event;
        $logger->info("Password reset request needed to be submitted before $threshold");
        return OpenILS::Event->new('PATRON_NOT_AN_ACTIVE_PASSWORD_RESET_REQUEST');
    }

    # Check complexity of password against OU-defined regex
    my $pw_regex = $U->ou_ancestor_setting_value($user->home_ou, 'global.password_regex');

    my $is_strong = 0;
    if ($pw_regex) {
        # Calling JSON2perl on the $pw_regex causes failure, even before the fancy Unicode regex
        # ($pw_regex = OpenSRF::Utils::JSON->JSON2perl($pw_regex)) =~ s/\\u([0-9a-fA-F]{4})/\\x{$1}/gs;
        $is_strong = check_password_strength_custom($password, $pw_regex);
    } else {
        $is_strong = check_password_strength_default($password);
    }

    if (!$is_strong) {
        $e->die_event;
        return OpenILS::Event->new('PATRON_PASSWORD_WAS_NOT_STRONG');
    }

    # All is well; update the password
    modify_migrated_user_password($e, $user->id, $password);

    # And flag that this password reset request has been honoured
    $aupr->[0]->has_been_reset('t');
    $e->update_actor_usr_password_reset($aupr->[0]);
    $e->commit;

    return 1;
}

sub check_password_strength_default {
    my $password = shift;
    # Use the default set of checks
    if ( (length($password) < 7) or
            ($password !~ m/.*\d+.*/) or
            ($password !~ m/.*[A-Za-z]+.*/)
    ) {
        return 0;
    }
    return 1;
}

sub check_password_strength_custom {
    my ($password, $pw_regex) = @_;

    $pw_regex = qr/$pw_regex/;
    if ($password !~  /$pw_regex/) {
        return 0;
    }
    return 1;
}

__PACKAGE__->register_method(
    method    => "fire_test_notification",
    api_name  => "open-ils.actor.event.test_notification"
);

sub fire_test_notification {
    my($self, $conn, $auth, $args) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    if ($e->requestor->id != $$args{target}) {
        my $home_ou = $e->retrieve_actor_user($$args{target})->home_ou;
        return $e->die_event unless $home_ou && $e->allowed('VIEW_USER', $home_ou);
    }

    my $event_hook = $$args{hook} or return $e->event;
    return $e->event unless ($event_hook eq 'au.email.test' or $event_hook eq 'au.sms_text.test');

    my $usr = $e->retrieve_actor_user($$args{target});
    return $e->event unless $usr;

    return $U->fire_object_event(undef, $event_hook, $usr, $e->requestor->ws_ou);
}


__PACKAGE__->register_method(
    method    => "event_def_opt_in_settings",
    api_name  => "open-ils.actor.event_def.opt_in.settings",
    stream => 1,
    signature => {
        desc   => 'Streams the set of "cust" objects that are used as opt-in settings for event definitions',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            {
                desc => 'Org Unit ID.  (optional).  If no org ID is present, the home_ou of the requesting user is used',
                type => 'number'
            },
        ],
        return => {
            desc => q/set of "cust" objects that are used as opt-in settings for event definitions at the specified org unit/,
            type => 'object',
            class => 'cust'
        }
    }
);

sub event_def_opt_in_settings {
    my($self, $conn, $auth, $org_id) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    if(defined $org_id and $org_id != $e->requestor->home_ou) {
        return $e->event unless
            $e->allowed(['VIEW_USER_SETTING_TYPE', 'ADMIN_USER_SETTING_TYPE'], $org_id);
    } else {
        $org_id = $e->requestor->home_ou;
    }

    # find all config.user_setting_type's related to event_defs for the requested org unit
    my $types = $e->json_query({
        select => {cust => ['name']},
        from => {atevdef => 'cust'},
        where => {
            '+atevdef' => {
                owner => $U->get_org_ancestors($org_id), # context org plus parents
                active => 't'
            }
        }
    });

    if(@$types) {
        $conn->respond($_) for
            @{$e->search_config_usr_setting_type({name => [map {$_->{name}} @$types]})};
    }

    return undef;
}


__PACKAGE__->register_method(
    method    => "user_circ_history",
    api_name  => "open-ils.actor.history.circ",
    stream => 1,
    authoritative => 1,
    signature => {
        desc   => 'Returns user circ history objects for the calling user',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'Options hash.  Supported fields are "limit" and "offset"', type => 'object' },
        ],
        return => {
            desc => q/Stream of 'auch' circ history objects/,
            type => 'object',
        }
    }
);

__PACKAGE__->register_method(
    method    => "user_circ_history",
    api_name  => "open-ils.actor.history.circ.clear",
    stream => 1,
    signature => {
        desc   => 'Delete all user circ history entries for the calling user',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => "Options hash. 'circ_ids' is an arrayref of circulation IDs to delete", type => 'object' },
        ],
        return => {
            desc => q/1 on success, event on error/,
            type => 'object',
        }
    }
);

__PACKAGE__->register_method(
    method    => "user_circ_history",
    api_name  => "open-ils.actor.history.circ.print",
    stream => 1,
    signature => {
        desc   => q/Returns printable output for the caller's circ history objects/,
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'Options hash.  Supported fields are "limit" and "offset"', type => 'object' },
        ],
        return => {
            desc => q/An action_trigger.event object or error event./,
            type => 'object',
        }
    }
);

__PACKAGE__->register_method(
    method    => "user_circ_history",
    api_name  => "open-ils.actor.history.circ.email",
    stream => 1,
    signature => {
        desc   => q/Emails the caller's circ history/,
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'User ID.  If no user id is present, the authenticated user is assumed', type => 'number' },
            { desc => 'Options hash.  Supported fields are "limit" and "offset"', type => 'object' },
        ],
        return => {
            desc => q/undef, or event on error/
        }
    }
);

sub user_circ_history {
    my ($self, $conn, $auth, $options) = @_;
    $options ||= {};

    my $for_print = ($self->api_name =~ /print/);
    my $for_email = ($self->api_name =~ /email/);
    my $for_clear = ($self->api_name =~ /clear/);

    # No perm check is performed.  Caller may only access his/her own
    # circ history entries.
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my %limits = ();
    if (!$for_clear) { # clear deletes all
        $limits{offset} = $options->{offset} if defined $options->{offset};
        $limits{limit} = $options->{limit} if defined $options->{limit};
    }

    my %circ_id_filter = $options->{circ_ids} ?
        (id => $options->{circ_ids}) : ();

    my $circs = $e->search_action_user_circ_history([
        {   usr => $e->requestor->id,
            %circ_id_filter
        },
        {   # order newest to oldest by default
            order_by => {auch => 'xact_start DESC'},
            %limits
        },
        {substream => 1} # could be a large list
    ]);

    if ($for_print) {
        return $U->fire_object_event(undef,
            'circ.format.history.print', $circs, $e->requestor->home_ou);
    }

    $e->xact_begin if $for_clear;
    $conn->respond_complete(1) if $for_email;  # no sense in waiting

    for my $circ (@$circs) {

        if ($for_email) {
            # events will be fired from action_trigger_runner
            $U->create_events_for_hook('circ.format.history.email',
                $circ, $e->editor->home_ou, undef, undef, 1);

        } elsif ($for_clear) {

            $e->delete_action_user_circ_history($circ)
                or return $e->die_event;

        } else {
            $conn->respond($circ);
        }
    }

    if ($for_clear) {
        $e->commit;
        return 1;
    }

    return undef;
}


__PACKAGE__->register_method(
    method    => "user_visible_holds",
    api_name  => "open-ils.actor.history.hold.visible",
    stream => 1,
    signature => {
        desc   => 'Returns the set of opt-in visible holds',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'User ID.  If no user id is present, the authenticated user is assumed', type => 'number' },
            { desc => 'Options hash.  Supported fields are "limit" and "offset"', type => 'object' },
        ],
        return => {
            desc => q/An object with 1 field: "hold"/,
            type => 'object',
        }
    }
);

__PACKAGE__->register_method(
    method    => "user_visible_holds",
    api_name  => "open-ils.actor.history.hold.visible.print",
    stream => 1,
    signature => {
        desc   => 'Returns printable output for the set of opt-in visible holds',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'User ID.  If no user id is present, the authenticated user is assumed', type => 'number' },
            { desc => 'Options hash.  Supported fields are "limit" and "offset"', type => 'object' },
        ],
        return => {
            desc => q/An action_trigger.event object or error event./,
            type => 'object',
        }
    }
);

__PACKAGE__->register_method(
    method    => "user_visible_holds",
    api_name  => "open-ils.actor.history.hold.visible.email",
    stream => 1,
    signature => {
        desc   => 'Emails the set of opt-in visible holds to the requestor',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'User ID.  If no user id is present, the authenticated user is assumed', type => 'number' },
            { desc => 'Options hash.  Supported fields are "limit" and "offset"', type => 'object' },
        ],
        return => {
            desc => q/undef, or event on error/
        }
    }
);

sub user_visible_holds {
    my($self, $conn, $auth, $user_id, $options) = @_;

    my $is_hold = 1;
    my $for_print = ($self->api_name =~ /print/);
    my $for_email = ($self->api_name =~ /email/);
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    $user_id ||= $e->requestor->id;
    $options ||= {};
    $options->{limit} ||= 50;
    $options->{offset} ||= 0;

    if($user_id != $e->requestor->id) {
        my $perm = ($is_hold) ? 'VIEW_HOLD' : 'VIEW_CIRCULATIONS';
        my $user = $e->retrieve_actor_user($user_id) or return $e->event;
        return $e->event unless $e->allowed($perm, $user->home_ou);
    }

    my $db_func = ($is_hold) ? 'action.usr_visible_holds' : 'action.usr_visible_circs';

    my $data = $e->json_query({
        from => [$db_func, $user_id],
        limit => $$options{limit},
        offset => $$options{offset}

        # TODO: I only want IDs. code below didn't get me there
        # {"select":{"au":[{"column":"id", "result_field":"id",
        # "transform":"action.usr_visible_circs"}]}, "where":{"id":10}, "from":"au"}
    },{
        substream => 1
    });

    return undef unless @$data;

    if ($for_print) {

        # collect the batch of objects

        if($is_hold) {

            my $hold_list = $e->search_action_hold_request({id => [map { $_->{id} } @$data]});
            return $U->fire_object_event(undef, 'ahr.format.history.print', $hold_list, $$hold_list[0]->request_lib);

        } else {

            my $circ_list = $e->search_action_circulation({id => [map { $_->{id} } @$data]});
            return $U->fire_object_event(undef, 'circ.format.history.print', $circ_list, $$circ_list[0]->circ_lib);
        }

    } elsif ($for_email) {

        $conn->respond_complete(1) if $for_email;  # no sense in waiting

        foreach (@$data) {

            my $id = $_->{id};

            if($is_hold) {

                my $hold = $e->retrieve_action_hold_request($id);
                $U->create_events_for_hook('ahr.format.history.email', $hold, $hold->request_lib, undef, undef, 1);
                # events will be fired from action_trigger_runner

            } else {

                my $circ = $e->retrieve_action_circulation($id);
                $U->create_events_for_hook('circ.format.history.email', $circ, $circ->circ_lib, undef, undef, 1);
                # events will be fired from action_trigger_runner
            }
        }

    } else { # just give me the data please

        foreach (@$data) {

            my $id = $_->{id};

            if($is_hold) {

                my $hold = $e->retrieve_action_hold_request($id);
                $conn->respond({hold => $hold});

            } else {

                my $circ = $e->retrieve_action_circulation($id);
                $conn->respond({
                    circ => $circ,
                    summary => $U->create_circ_chain_summary($e, $id)
                });
            }
        }
    }

    return undef;
}

__PACKAGE__->register_method(
    method     => "user_saved_search_cud",
    api_name   => "open-ils.actor.user.saved_search.cud",
    stream     => 1,
    signature  => {
        desc   => 'Create/Update/Delete Access to user saved searches',
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Saved Search Object', type => 'object', class => 'auss' }
        ],
        return => {
            desc   => q/The retrieved or updated saved search object, or id of a deleted object; Event on error/,
            class  => 'auss'
        }
    }
);

__PACKAGE__->register_method(
    method     => "user_saved_search_cud",
    api_name   => "open-ils.actor.user.saved_search.retrieve",
    stream     => 1,
    signature  => {
        desc   => 'Retrieve a saved search object',
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Saved Search ID', type => 'number' }
        ],
        return => {
            desc   => q/The saved search object, Event on error/,
            class  => 'auss'
        }
    }
);

sub user_saved_search_cud {
    my( $self, $client, $auth, $search ) = @_;
    my $e = new_editor( authtoken=>$auth );
    return $e->die_event unless $e->checkauth;

    my $o_search;      # prior version of the object, if any
    my $res;           # to be returned

    # branch on the operation type

    if( $self->api_name =~ /retrieve/ ) {                    # Retrieve

        # Get the old version, to check ownership
        $o_search = $e->retrieve_actor_usr_saved_search( $search )
            or return $e->die_event;

        # You can't read somebody else's search
        return OpenILS::Event->new('BAD_PARAMS')
            unless $o_search->owner == $e->requestor->id;

        $res = $o_search;

    } else {

        $e->xact_begin;               # start an editor transaction

        if( $search->isnew ) {                               # Create

            # You can't create a search for somebody else
            return OpenILS::Event->new('BAD_PARAMS')
                unless $search->owner == $e->requestor->id;

            $e->create_actor_usr_saved_search( $search )
                or return $e->die_event;

            $res = $search->id;

        } elsif( $search->ischanged ) {                      # Update

            # You can't change ownership of a search
            return OpenILS::Event->new('BAD_PARAMS')
                unless $search->owner == $e->requestor->id;

            # Get the old version, to check ownership
            $o_search = $e->retrieve_actor_usr_saved_search( $search->id )
                or return $e->die_event;

            # You can't update somebody else's search
            return OpenILS::Event->new('BAD_PARAMS')
                unless $o_search->owner == $e->requestor->id;

            # Do the update
            $e->update_actor_usr_saved_search( $search )
                or return $e->die_event;

            $res = $search;

        } elsif( $search->isdeleted ) {                      # Delete

            # Get the old version, to check ownership
            $o_search = $e->retrieve_actor_usr_saved_search( $search->id )
                or return $e->die_event;

            # You can't delete somebody else's search
            return OpenILS::Event->new('BAD_PARAMS')
                unless $o_search->owner == $e->requestor->id;

            # Do the delete
            $e->delete_actor_usr_saved_search( $o_search )
                or return $e->die_event;

            $res = $search->id;
        }

        $e->commit;
    }

    return $res;
}

__PACKAGE__->register_method(
    method   => "get_barcodes",
    api_name => "open-ils.actor.get_barcodes"
);

sub get_barcodes {
    my( $self, $client, $auth, $org_id, $context, $barcode ) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('STAFF_LOGIN', $org_id);

    my $db_result = $e->json_query(
        {   from => [
                'evergreen.get_barcodes',
                $org_id, $context, $barcode,
            ]
        }
    );
    if($context =~ /actor/) {
        my $filter_result = ();
        my $patron;
        foreach my $result (@$db_result) {
            if($result->{type} eq 'actor') {
                if($e->requestor->id != $result->{id}) {
                    $patron = $e->retrieve_actor_user($result->{id});
                    if(!$patron) {
                        push(@$filter_result, $e->event);
                        next;
                    }
                    if($e->allowed('VIEW_USER', $patron->home_ou)) {
                        push(@$filter_result, $result);
                    }
                    else {
                        push(@$filter_result, $e->event);
                    }
                }
                else {
                    push(@$filter_result, $result);
                }
            }
            else {
                push(@$filter_result, $result);
            }
        }
        return $filter_result;
    }
    else {
        return $db_result;
    }
}
__PACKAGE__->register_method(
    method   => 'address_alert_test',
    api_name => 'open-ils.actor.address_alert.test',
    signature => {
        desc => "Tests a set of address fields to determine if they match with an address_alert",
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Org Unit',             type => 'number'},
            {desc => 'Fields',               type => 'hash'},
        ],
        return => {desc => 'List of matching address_alerts'}
    }
);

sub address_alert_test {
    my ($self, $client, $auth, $org_unit, $fields) = @_;
    return [] unless $fields and grep {$_} values %$fields;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('CREATE_USER', $org_unit);
    $org_unit ||= $e->requestor->ws_ou;

    my $alerts = $e->json_query({
        from => [
            'actor.address_alert_matches',
            $org_unit,
            $$fields{street1},
            $$fields{street2},
            $$fields{city},
            $$fields{county},
            $$fields{state},
            $$fields{country},
            $$fields{post_code},
            $$fields{mailing_address},
            $$fields{billing_address}
        ]
    });

    # map the json_query hashes to real objects
    return [
        map {$e->retrieve_actor_address_alert($_)}
            (map {$_->{id}} @$alerts)
    ];
}

__PACKAGE__->register_method(
    method   => "mark_users_contact_invalid",
    api_name => "open-ils.actor.invalidate.email",
    signature => {
        desc => "Given a patron or email address, clear the email field for one patron or all patrons with that email address and put the old email address into a note and/or create a standing penalty, depending on OU settings",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Patron ID (optional if Email address specified)", type => "number"},
            {desc => "Additional note text (optional)", type => "string"},
            {desc => "penalty org unit ID (optional)", type => "number"},
            {desc => "Email address (optional)", type => "string"}
        ],
        return => {desc => "Event describing success or failure", type => "object"}
    }
);

__PACKAGE__->register_method(
    method   => "mark_users_contact_invalid",
    api_name => "open-ils.actor.invalidate.day_phone",
    signature => {
        desc => "Given a patron or phone number, clear the day_phone field for one patron or all patrons with that day_phone number and put the old day_phone into a note and/or create a standing penalty, depending on OU settings",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Patron ID (optional if Phone Number specified)", type => "number"},
            {desc => "Additional note text (optional)", type => "string"},
            {desc => "penalty org unit ID (optional)", type => "number"},
            {desc => "Phone Number (optional)", type => "string"}
        ],
        return => {desc => "Event describing success or failure", type => "object"}
    }
);

__PACKAGE__->register_method(
    method   => "mark_users_contact_invalid",
    api_name => "open-ils.actor.invalidate.evening_phone",
    signature => {
        desc => "Given a patron or phone number, clear the evening_phone field for one patron or all patrons with that evening_phone number and put the old evening_phone into a note and/or create a standing penalty, depending on OU settings",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Patron ID (optional if Phone Number specified)", type => "number"},
            {desc => "Additional note text (optional)", type => "string"},
            {desc => "penalty org unit ID (optional)", type => "number"},
            {desc => "Phone Number (optional)", type => "string"}
        ],
        return => {desc => "Event describing success or failure", type => "object"}
    }
);

__PACKAGE__->register_method(
    method   => "mark_users_contact_invalid",
    api_name => "open-ils.actor.invalidate.other_phone",
    signature => {
        desc => "Given a patron or phone number, clear the other_phone field for one patron or all patrons with that other_phone number and put the old other_phone into a note and/or create a standing penalty, depending on OU settings",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Patron ID (optional if Phone Number specified)", type => "number"},
            {desc => "Additional note text (optional)", type => "string"},
            {desc => "penalty org unit ID (optional, default to top of org tree)",
                type => "number"},
            {desc => "Phone Number (optional)", type => "string"}
        ],
        return => {desc => "Event describing success or failure", type => "object"}
    }
);

sub mark_users_contact_invalid {
    my ($self, $conn, $auth, $patron_id, $addl_note, $penalty_ou, $contact) = @_;

    # This method invalidates an email address or a phone_number which
    # removes the bad email address or phone number, copying its contents
    # to a patron note, and institutes a standing penalty for "bad email"
    # or "bad phone number" which is cleared when the user is saved or
    # optionally only when the user is saved with an email address or
    # phone number (or staff manually delete the penalty).

    my $contact_type = ($self->api_name =~ /invalidate.(\w+)(\.|$)/)[0];

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    
    my $howfind = {};
    if (defined $patron_id && $patron_id ne "") {
        $howfind = {usr => $patron_id};
    } elsif (defined $contact && $contact ne "") {
        $howfind = {$contact_type => $contact};
    } else {
        # Error out if no patron id set or no contact is set.
        return OpenILS::Event->new('BAD_PARAMS');
    }
 
    return OpenILS::Utils::BadContact->mark_users_contact_invalid(
        $e, $contact_type, $howfind,
        $addl_note, $penalty_ou, $e->requestor->id
    );
}

# Putting the following method in open-ils.actor is a bad fit, except in that
# it serves an interface that lives under 'actor' in the templates directory,
# and in that there's nowhere else obvious to put it (open-ils.trigger is
# private).
__PACKAGE__->register_method(
    api_name => "open-ils.actor.action_trigger.reactors.all_in_use",
    method   => "get_all_at_reactors_in_use",
    api_level=> 1,
    argc     => 1,
    signature=> {
        params => [
            { name => 'authtoken', type => 'string' }
        ],
        return => {
            desc => 'list of reactor names', type => 'array'
        }
    }
);

sub get_all_at_reactors_in_use {
    my ($self, $conn, $auth) = @_;

    my $e = new_editor(authtoken => $auth);
    $e->checkauth or return $e->die_event;
    return $e->die_event unless $e->allowed('VIEW_TRIGGER_EVENT_DEF');

    my $reactors = $e->json_query({
        select => {
            atevdef => [{column => "reactor", transform => "distinct"}]
        },
        from => {atevdef => {}}
    });

    return $e->die_event unless ref $reactors eq "ARRAY";
    $e->disconnect;

    return [ map { $_->{reactor} } @$reactors ];
}

__PACKAGE__->register_method(
    method   => "filter_group_entry_crud",
    api_name => "open-ils.actor.filter_group_entry.crud",
    signature => {
        desc => q/
            Provides CRUD access to filter group entry objects.  These are not full accessible
            via PCRUD, since they requre "asq" objects for storing the query, and "asq" objects
            are not accessible via PCRUD (because they have no fields against which to link perms)
            /,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Entry ID / Entry Object", type => "number"},
            {desc => "Additional note text (optional)", type => "string"},
            {desc => "penalty org unit ID (optional, default to top of org tree)",
                type => "number"}
        ],
        return => {
            desc => "Entry fleshed with query on Create, Retrieve, and Uupdate.  1 on Delete",
            type => "object"
        }
    }
);

sub filter_group_entry_crud {
    my ($self, $conn, $auth, $arg) = @_;

    return OpenILS::Event->new('BAD_PARAMS') unless $arg;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    if (ref $arg) {

        if ($arg->isnew) {

            my $grp = $e->retrieve_actor_search_filter_group($arg->grp)
                or return $e->die_event;

            return $e->die_event unless $e->allowed(
                'ADMIN_SEARCH_FILTER_GROUP', $grp->owner);

            my $query = $arg->query;
            $query = $e->create_actor_search_query($query) or return $e->die_event;
            $arg->query($query->id);
            my $entry = $e->create_actor_search_filter_group_entry($arg) or return $e->die_event;
            $entry->query($query);

            $e->commit;
            return $entry;

        } elsif ($arg->ischanged) {

            my $entry = $e->retrieve_actor_search_filter_group_entry([
                $arg->id, {
                    flesh => 1,
                    flesh_fields => {asfge => ['grp']}
                }
            ]) or return $e->die_event;

            return $e->die_event unless $e->allowed(
                'ADMIN_SEARCH_FILTER_GROUP', $entry->grp->owner);

            my $query = $e->update_actor_search_query($arg->query) or return $e->die_event;
            $arg->query($arg->query->id);
            $e->update_actor_search_filter_group_entry($arg) or return $e->die_event;
            $arg->query($query);

            $e->commit;
            return $arg;

        } elsif ($arg->isdeleted) {

            my $entry = $e->retrieve_actor_search_filter_group_entry([
                $arg->id, {
                    flesh => 1,
                    flesh_fields => {asfge => ['grp', 'query']}
                }
            ]) or return $e->die_event;

            return $e->die_event unless $e->allowed(
                'ADMIN_SEARCH_FILTER_GROUP', $entry->grp->owner);

            $e->delete_actor_search_filter_group_entry($entry) or return $e->die_event;
            $e->delete_actor_search_query($entry->query) or return $e->die_event;

            $e->commit;
            return 1;

        } else {

            $e->rollback;
            return undef;
        }

    } else {

        my $entry = $e->retrieve_actor_search_filter_group_entry([
            $arg, {
                flesh => 1,
                flesh_fields => {asfge => ['grp', 'query']}
            }
        ]) or return $e->die_event;

        return $e->die_event unless $e->allowed(
            ['ADMIN_SEARCH_FILTER_GROUP', 'VIEW_SEARCH_FILTER_GROUP'],
            $entry->grp->owner);

        $e->rollback;
        $entry->grp($entry->grp->id); # for consistency
        return $entry;
    }
}

__PACKAGE__->register_method(
    method   => "get_staff_client_cache_key",
    api_name => "open-ils.actor.staff_client_cache_key",
    signature => {
        desc => q/
            Return a key that the staff client can use to
            determine whether it should purge long-cached objects
            /,
        return => {
            desc => "An opaque cache key",
            type => "string"
        }
    }
);

sub get_staff_client_cache_key {
    my $self = shift;

    my $value = $U->get_global_flag('staff.client_cache_key');

    $value = $value->value() if $value;
    # Undef is an unfriendly "not found"
    $value = "BleepBloopNoKey" unless $value;

    return $value;
}

1;
