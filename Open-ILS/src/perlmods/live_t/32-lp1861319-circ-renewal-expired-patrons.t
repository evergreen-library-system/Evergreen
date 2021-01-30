#!perl
use strict; use warnings;
use Test::More tests => 18;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);
use OpenILS::Utils::DateTime;
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::ISO8601;

# We need the local timezone for later.
my $localTZ = DateTime::TimeZone->new(name => 'local');

my $script = OpenILS::Utils::TestUtils->new();
my $U = 'OpenILS::Application::AppUtils';

diag("Test LP 1861319 Allow Circulation Renewal for Expired Patrons");

use constant {
    BR1_ID => 4,
    BR2_ID => 6,
    BR1_WORKSTATION => 'BR1-lp1861319-test-renewal',
    BR2_WORKSTATION => 'BR2-lp1861319-test renewal',
    ADMIN_USER => 'admin',
    ADMIN_PASS => 'demo123'
};

# Login
$script->authenticate({
    username => ADMIN_USER,
    password => ADMIN_PASS,
    type => 'staff'
});
BAIL_OUT('Failed to Login') unless ($script->authtoken);

# Register BR1 workstation.
my $ws = $script->find_or_register_workstation(BR1_WORKSTATION, BR1_ID);
BAIL_OUT("Failed to register " . BR1_WORKSTATION) unless($ws);

# Logout
$script->logout();

# Login with BR1 Workstation
$script->authenticate({
    username => ADMIN_USER,
    password => ADMIN_PASS,
    type => 'staff',
    workstation => BR1_WORKSTATION
});
BAIL_OUT('Failed to login with ' . BR1_WORKSTATION) unless($script->authtoken);

# Get a cstore editor for later use.
my $editor = $script->editor(authtoken=>$script->authtoken);

# Check that the circ.renew.expired_patron_allow setting constant is defined
ok(defined(OILS_SETTING_ALLOW_RENEW_FOR_EXPIRED_PATRON),
   'OILS_SETTING_ALLOW_RENEW_FOR_EXPIRED_PATRON constant exists');

# Check that the circ.renew.expired_patron_allow setting exists in the database
my $setting = $editor->search_config_org_unit_setting_type(
    {name => OILS_SETTING_ALLOW_RENEW_FOR_EXPIRED_PATRON}
);
# Get the first/only one:
$setting = (defined($setting)) ? $setting->[0] : $setting;
ok(defined($setting), OILS_SETTING_ALLOW_RENEW_FOR_EXPIRED_PATRON . ' setting exists in database');

# Find a circulation with renewals remaining
my $circ = $editor->search_action_circulation([
    {
        circ_lib => BR1_ID,
        checkin_time => undef,
        renewal_remaining => {'>' => 0}
    },
    {limit => 1}
]);
$circ = defined($circ) ? $circ->[0] : $circ;
isa_ok($circ, 'Fieldmapper::action::circulation', 'Found open circulation at BR1');

# Get the circ patron information.
my $patron = $editor->retrieve_actor_user($circ->usr);
isa_ok($patron, 'Fieldmapper::actor::user', 'Found circulation user');

# Expire the patron if they are not already expired.
my ($saved_expire_date);
SKIP: {
    if (check_usr_expired($patron)) {
        skip 'Patron already expired', 1;
    } else {
        $saved_expire_date = $patron->expire_date;
        $patron->expire_date(DateTime->now()->set_time_zone($localTZ)->subtract(days => 1)->strftime('%FT%T%z'));
        $editor->xact_begin;
        if ($editor->update_actor_user($patron)) {
            $editor->xact_commit;
        } else {
            $editor->xact_rollback;
            BAIL_OUT("Patron update failed");
        }
        $patron = $editor->retrieve_actor_user($patron->id);
        ok(check_usr_expired($patron), 'Patron set to expired.');
    }
}

# Attempt a renewal. It should fail.
my $renew_params = {
    copy_id => $circ->target_copy,
    patron_id => $circ->usr,
    desk_renewal => 1
};
my $result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.renew.override',
    $script->authtoken,
    $renew_params
);
if (ref($result) eq 'ARRAY') {
    $result = $result->[0];
}
is($result->{textcode}, 'PATRON_ACCOUNT_EXPIRED', 'Renewal failed: ' . $result->{textcode});

# Set the circ.renew.expired_patron_allow setting at BR1
$setting = Fieldmapper::actor::org_unit_setting->new;
$setting->name(OILS_SETTING_ALLOW_RENEW_FOR_EXPIRED_PATRON);
$setting->org_unit(BR1_ID);
$setting->value('true');
$editor->xact_begin;
$result = $editor->create_actor_org_unit_setting($setting);
if ($result) {
    $editor->xact_commit;
    ok($result, 'Set ' . OILS_SETTING_ALLOW_RENEW_FOR_EXPIRED_PATRON . ' for BR1');
} else {
    $editor->xact_rollback;
    BAIL_OUT("Failed to set " . OILS_SETTING_ALLOW_RENEW_FOR_EXPIRED_PATRON . ' for BR1');
}

# Attempt the renewal again, expect success.
$result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.renew.override',
    $script->authtoken,
    $renew_params
);
if (ref($result) eq 'ARRAY') {
    $result = $result->[0];
}
isnt($result->{textcode}, 'PATRON_ACCOUNT_EXPIRED', 'Renewal Result: ' . $result->{textcode});

# Find a circulating copy at BR1 that is not checked out.
my $copy = $editor->search_asset_copy([
    {
        circ_lib => BR1_ID,
        status => OILS_COPY_STATUS_AVAILABLE,
        circulate => 't'
    },
    {limit => 1}
]);
$copy = defined($copy) ? $copy->[0] : $copy;
isa_ok($copy, 'Fieldmapper::asset::copy', 'Found copy at BR1');

# Check it out, expect failure
my $checkout_params = {
    copy_id => $copy->id,
    patron_id => $patron->id
};
$result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.checkout.full.override',
    $script->authtoken,
    $checkout_params
);
if (ref($result) eq 'ARRAY') {
    $result = $result->[0];
}
is($result->{textcode}, 'PATRON_ACCOUNT_EXPIRED', 'Checkout failed: ' . $result->{textcode});

# Reset the patron expire_date
if (defined($saved_expire_date)) {
    $patron->expire_date($saved_expire_date);
    $editor->xact_begin;
    if ($editor->update_actor_user($patron)) {
        $editor->xact_commit;
    } else {
        $editor->xact_rollback;
    }
    undef($saved_expire_date);
}

# Logout
$script->logout();

# Destroy our editor.
undef($editor);

# Login
$script->authenticate({
    username => ADMIN_USER,
    password => ADMIN_PASS,
    type => 'staff'
});
BAIL_OUT('Failed to Login') unless ($script->authtoken);

# Register BR2 workstation.
$ws = $script->find_or_register_workstation(BR2_WORKSTATION, BR2_ID);
BAIL_OUT("Failed to register " . BR2_WORKSTATION) unless($ws);

# Logout
$script->logout();

# Login with BR2 Workstation
$script->authenticate({
    username => ADMIN_USER,
    password => ADMIN_PASS,
    type => 'staff',
    workstation => BR2_WORKSTATION
});
BAIL_OUT('Failed to login with ' . BR2_WORKSTATION) unless($script->authtoken);

# Get a new editor with our authtoken.
$editor = $script->editor(authtoken=>$script->authtoken);

# Find a circulation with renewals remaining at BR2
$circ = $editor->search_action_circulation([
    {
        circ_lib => BR2_ID,
        checkin_time => undef,
        renewal_remaining => {'>' => 0}
    },
    {limit => 1}
]);
$circ = defined($circ) ? $circ->[0] : $circ;
isa_ok($circ, 'Fieldmapper::action::circulation', 'Found open circulation at BR2');

# Get the circ patron information.
$patron = $editor->retrieve_actor_user($circ->usr);
isa_ok($patron, 'Fieldmapper::actor::user', 'Found circulation user');

# Expire the patron if they are not already expired.
SKIP: {
    if (check_usr_expired($patron)) {
        skip 'Patron already expired', 1;
    } else {
        $saved_expire_date = $patron->expire_date;
        $patron->expire_date(DateTime->now()->set_time_zone($localTZ)->subtract(days => 1)->strftime('%FT%T%z'));
        $editor->xact_begin;
        if ($editor->update_actor_user($patron)) {
            $editor->xact_commit;
            $patron = $editor->retrieve_actor_user($patron->id);
            ok(check_usr_expired($patron), 'Patron set to expired.');
        } else {
            $editor->xact_rollback;
            BAIL_OUT("Patron update failed");
        }
    }
}

# Attempt a renewal. It should fail.
$renew_params = {
    copy_id => $circ->target_copy,
    patron_id => $circ->usr,
    desk_renewal => 1
};
$result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.renew.override',
    $script->authtoken,
    $renew_params
);
if (ref($result) eq 'ARRAY') {
    $result = $result->[0];
}
is($result->{textcode}, 'PATRON_ACCOUNT_EXPIRED', 'Renewal failed: ' . $result->{textcode});

# Reset the patron expire_date
if (defined($saved_expire_date)) {
    $patron->expire_date($saved_expire_date);
    $editor->xact_begin;
    if ($editor->update_actor_user($patron)) {
        $editor->xact_commit;
        ok(!check_usr_expired($patron), 'Patron set to not expired');
    } else {
        $editor->xact_rollback;
        BAIL_OUT('Patron expire date reset failed');
    }
    undef($saved_expire_date);
} else {
    # Set patron expire date to 30 days in the future.
    $saved_expire_date = $patron->expire_date;
    $patron->expire_date(DateTime->now()->set_time_zone($localTZ)->add(days => 30)->strftime('%FT%T%z'));
    $editor->xact_begin;
    if ($editor->update_actor_user($patron)) {
        $editor->xact_commit;
        $patron = $editor->retrieve_actor_user($patron->id);
        ok(!check_usr_expired($patron), 'Patron is not expired.');
    } else {
        $editor->xact_rollback;
        BAIL_OUT("Patron update failed");
    }
}

# Attempt renewal, expect success.
$result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.renew.override',
    $script->authtoken,
    $renew_params
);
if (ref($result) eq 'ARRAY') {
    $result = $result->[0];
}
isnt($result->{textcode}, 'PATRON_ACCOUNT_EXPIRED', 'Renewal Result: ' . $result->{textcode});

# Find a circulating copy at BR2 that is not checked out.
$copy = $editor->search_asset_copy([
    {
        circ_lib => BR2_ID,
        status => OILS_COPY_STATUS_AVAILABLE,
        circulate => 't'
    },
    {limit => 1}
]);
$copy = defined($copy) ? $copy->[0] : $copy;
isa_ok($copy, 'Fieldmapper::asset::copy', 'Found copy at BR2');

# Check it out, expect failure
$checkout_params = {
    copy_id => $copy->id,
    patron_id => $patron->id
};
$result = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.checkout.full.override',
    $script->authtoken,
    $checkout_params
);
if (ref($result) eq 'ARRAY') {
    $result = $result->[0];
}
isnt($result->{textcode}, 'PATRON_ACCOUNT_EXPIRED', 'Checkout result: ' . $result->{textcode});

# Reset the patron expire_date if necessary
if (defined($saved_expire_date)) {
    $patron->expire_date($saved_expire_date);
    $editor->xact_begin;
    if ($editor->update_actor_user($patron)) {
        $editor->xact_commit;
    } else {
        $editor->xact_rollback;
    }
    undef($saved_expire_date);
}

# Delete the setting from actor.org_unit_setting
$editor->xact_begin;
if ($editor->delete_actor_org_unit_setting($setting)) {
    $editor->commit; # Commit so that we disconnect.
} else {
    $editor->rollback;
}

# Logout
$script->logout(); # Not a test, just to be pedantic.

# Utiity functions
sub check_usr_expired {
    my ($user) = @_;
    my $expire = DateTime::Format::ISO8601->new->parse_datetime(
        OpenILS::Utils::DateTime->clean_ISO8601($user->expire_date));
    return (time > $expire->epoch);
}
