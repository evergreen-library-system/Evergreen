package OpenILS::Application::Actor::Settings;
use strict; use warnings;
use base 'OpenILS::Application';
use OpenSRF::AppSession;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::JSON;
use OpenILS::Event;
my $U = "OpenILS::Application::AppUtils";

# Setting names may only contains letters, numbers, unders, and dots.
my $name_regex = qr/[^a-zA-Z0-9_\.]/;

__PACKAGE__->register_method (
    method      => 'retrieve_settings',
    api_name    => 'open-ils.actor.settings.retrieve',
    stream      => 1,
    signature => {
        desc => q/
            Returns org unit, user, and workstation setting values
            for the requested setting types.

            The API makes a best effort to find the correct setting
            value based on the available context data.

            If no auth token is provided, only publicly visible org
            unit settings may be returned.

            If no workstation is linked to the provided auth token, only
            user settings and perm-visible org unit settings may be
            returned.

            If no org unit is provided, but a workstation is linked to the
            auth token, the owning lib of the workstation is used as the
            context org unit.
        /,
        params => [
            {desc => 'settings. List of setting names', type => 'array'},
            {desc => 'authtoken. Optional', type => 'string'},
            {desc => 'org_id. Optional', type => 'number'}
        ],
        return => {
            desc => q/
                Stream of setting name=>value pairs in the same order
                as the provided list of setting names.  No key-value
                pair is returned for settings that have no value defined./,
            type => 'string'
        }
    }
);

sub retrieve_settings {
    my ($self, $client, $settings, $auth, $org_id) = @_;

    my ($aou_id, $user_id, $ws_id, $evt) = get_context($auth, $org_id);
    return $evt if $evt; # bogus auth token

    return OpenILS::Event->new('BAD_PARAMS',
        desc => 'Cannot retrieve settings without a user or org unit')
        unless ($user_id || $aou_id);

    # Setting names may only contains letters, numbers, unders, and dots.
    s/$name_regex//g foreach @$settings;

    # Encode as a db-friendly array.
    my $settings_str = '{' . join(',', @$settings) . '}';

    # Some settings could be bulky, so fetch them as a stream from
    # cstore, relaying values back to the caller as they arrive.
    my $ses = OpenSRF::AppSession->create('open-ils.cstore');
    my $req = $ses->request('open-ils.cstore.json_query', {
        from => [
            'actor.get_cascade_setting_batch',
            $settings_str, $aou_id, $user_id, $ws_id
        ]
    });

    while (my $resp = $req->recv) {
        my $summary = $resp->content;
        $summary->{value} = OpenSRF::Utils::JSON->JSON2perl($summary->{value});
        $client->respond($summary);
    }

    $ses->kill_me;
    return undef;
}

# Returns ($org_id, $user_id, $ws_id, $evt);
# Any value may be undef.
sub get_context {
    my ($auth, $org_id) = @_;

    return ($org_id) unless $auth;

    my $e = new_editor(authtoken => $auth);
    return (undef, undef, undef, $e->event) unless $e->checkauth;

    my $user_id = $e->requestor->id;
    my $ws_id = $e->requestor->wsid;

    # default to the workstation org if needed.
    $org_id = $e->requestor->ws_ou if $ws_id && !$org_id;

    return ($org_id, $user_id, $ws_id);
}

__PACKAGE__->register_method (
    method      => 'apply_user_or_ws_setting',
    api_name    => 'open-ils.actor.settings.apply.user_or_ws',
    stream      => 1,
    signature => {
        desc => q/
            Apply values to user or workstation settings, depending
            on which is supported via local configuration.

            The API ignores nonexistent settings and only returns error
            events when an auth, permission, or internal error occurs.
        /,
        params => [
            {desc => 'authtoken', type => 'string'},
            {desc => 'settings. Hash of key/value pairs', type => 'object'},
        ],
        return => {
            desc => 'Returns the number of applied settings on succes, Event on error.',
            type => 'number or event'
        }
    }
);

sub apply_user_or_ws_setting {
    my ($self, $client, $auth, $settings) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $applied = 0;
    my $ws_allowed = 0;

    for my $name (keys %$settings) {
        $name =~ s/$name_regex//g;
        my $val = $$settings{$name};
        my $stype = $e->retrieve_config_usr_setting_type($name);

        if ($stype) {
            my $evt = apply_user_setting($e, $name, $val);
            return $evt if $evt;
            $applied++;

        } elsif ($e->requestor->wsid) {
            $stype = $e->retrieve_config_workstation_setting_type($name);
            next unless $stype; # no such workstation setting, skip.

            if (!$ws_allowed) {
                # Confirm the caller has permission to apply workstation
                # settings at the logged-in workstation before applying.
                # Do the perm check here so it's only needed once per batch.
                return $e->die_event unless
                    $ws_allowed = $e->allowed('APPLY_WORKSTATION_SETTING');
            }

            my $evt = apply_workstation_setting($e, $name, $val);
            return $evt if $evt;
            $applied++;
        }
    }

    $e->commit if $applied > 0;
    $e->rollback if $applied == 0;

    return $applied;
}

# CUD for user settings.
# Returns undef on success, Event on error.
# NOTE: This code was copied as-is from
# open-ils.actor.patron.settings.update, because it lets us
# manage the batch of updates within a single transaction.  Also
# worth noting the APIs in this mod could eventually replace
# open-ils.actor.patron.settings.update.  Maybe.
sub apply_user_setting {
    my ($e, $name, $val) = @_;
    my $user_id = $e->requestor->id;

    my $set = $e->search_actor_user_setting(
        {usr => $user_id, name => $name})->[0];

    if (defined $val) {
        $val = OpenSRF::Utils::JSON->perl2JSON($val);
        if ($set) {
            $set->value($val);
            $e->update_actor_user_setting($set) or return $e->die_event;
        } else {
            $set = Fieldmapper::actor::user_setting->new;
            $set->usr($user_id);
            $set->name($name);
            $set->value($val);
            $e->create_actor_user_setting($set) or return $e->die_event;
        }
    } elsif ($set) {
        $e->delete_actor_user_setting($set) or return $e->die_event;
    }

    return undef;
}

# CUD for workstation settings.
# Assumes ->wsid contains a value and permissions have been checked.
# Returns undef on success, Event on error.
sub apply_workstation_setting {
    my ($e, $name, $val) = @_;
    my $ws_id = $e->requestor->wsid;

    my $set = $e->search_actor_workstation_setting(
        {workstation => $ws_id, name => $name})->[0];

    if (defined $val) {
        $val = OpenSRF::Utils::JSON->perl2JSON($val);

        if ($set) {
            $set->value($val);
            $e->update_actor_workstation_setting($set) or return $e->die_event;
        } else {
            $set = Fieldmapper::actor::workstation_setting->new;
            $set->workstation($ws_id);
            $set->name($name);
            $set->value($val);
            $e->create_actor_workstation_setting($set) or return $e->die_event;
        }
    } elsif ($set) {
        $e->delete_actor_workstation_setting($set) or return $e->die_event;
    }

    return undef;
}

__PACKAGE__->register_method (
    method      => 'applied_settings',
    api_name    => 'open-ils.actor.settings.staff.applied.names',
    stream      => 1,
    authoritative => 1,
    signature => {
        desc => q/
            Returns a list of setting names where a value is applied to
            the current user or workstation.

            This is a staff-only API created primarily to support the
            getKeys() functionality used in the browser client for
            server-managed settings.

            Note as of now, this API can return names for user settings
            which are unrelated to the staff client.  ALL user setting
            names matching the selected prefix are returned!

            Use the workstation_only option to avoid returning any user
            setting names.

        /,
        params => [
            {desc => 'authtoken', type => 'string'},
            {desc =>
                'prefix.  Limit keys to those starting with $prefix',
             type => 'string'
            },
        ],
        return => {
            desc => 'List of strings, Event on error',
            type => 'array'
        }
    }
);

sub applied_settings {
    my ($self, $client, $auth, $prefix, $options) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('STAFF_LOGIN');

    $options ||= {};

    my $query = {
        select => {awss => ['name']},
        from => 'awss',
        where => {
            workstation => $e->requestor->wsid
        }
    };

    $query->{where}->{name} = {like => "$prefix%"} if $prefix;

    for my $key (@{$e->json_query($query)}) {
        $client->respond($key->{name});
    }

    return undef if $options->{workstation_only};

    $query = {
        select => {aus => ['name']},
        from => 'aus',
        where => {
            usr => $e->requestor->id
        }
    };

    $query->{where}->{name} = {like => "$prefix%"} if $prefix;

    for my $key (@{$e->json_query($query)}) {
        $client->respond($key->{name});
    }

    return undef;
}



1;
