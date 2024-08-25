#!perl
use strict; use warnings;
use Test::More tests => 30;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);

diag("Test LP 1694058 multiple hold placement.");

my $script = OpenILS::Utils::TestUtils->new();
my $U = 'OpenILS::Application::AppUtils';

use constant {
    BR1_WORKSTATION => 'BR1-test-lp1694058-multiple-hold-placement.t',
    BR1_ID => 4,
    BR2_ID => 5,
    PATRON1_BARCODE => '99999376864',
    PATRON2_BARCODE => '99999342948',
    RECORD_ID => 3,
    METARECORD_ID => 13,
    COPY_ID => 2503,
};

# Keep track of hold ids, so we can cancel them later.
my @holds = ();

# Login as admin at BR1.
my $authtoken = $script->authenticate({
    username=>'admin',
    password=>'demo123',
    type=>'staff'
});
ok(
    $script->authtoken,
    'Have an authtoken'
);

# Register workstation.
my $ws = $script->find_or_register_workstation(BR1_WORKSTATION, BR1_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
);

# Logout.
$script->logout();
ok(
    ! $script->authtoken,
    'Successfully logged out'
);

# Login as admin at BR1 using the workstation.
$authtoken = $script->authenticate({
    username=>'admin',
    password=>'demo123',
    type=>'staff',
    workstation => BR1_WORKSTATION
});
ok(
    $script->authtoken,
    'Have an authtoken'
);

# Check that OILS_SETTING_MAX_DUPLICATE_HOLDS is not set at BR1 and ancestors.
my $setting_value = $U->ou_ancestor_setting_value(BR1_ID, OILS_SETTING_MAX_DUPLICATE_HOLDS);
ok(
    ! $setting_value,
    'circ.holds.max_duplicate_holds is not set for BR1'
);

# Check that OILS_SETTING_MAX_DUPLICATE_HOLDS is not set at BR2 and ancestors.
$setting_value = $U->ou_ancestor_setting_value(BR2_ID, OILS_SETTING_MAX_DUPLICATE_HOLDS);
ok(
    ! $setting_value,
    'circ.holds.max_duplicate_holds is not set for BR2'
);

# Set OILS_SETTING_MAX_DUPLICATE_HOLDS to 5 at BR1.
$setting_value = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $authtoken,
    BR1_ID,
    {OILS_SETTING_MAX_DUPLICATE_HOLDS, 5}
);
ok(
    ! ref $setting_value,
    'circ.holds.max_duplicate_holds set to 5 for BR1'
);

# Retrieve PATRON1.
my $patron1 = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.fleshed.retrieve_by_barcode',
    $authtoken,
    PATRON1_BARCODE
);
isa_ok(
    ref $patron1,
    'Fieldmapper::actor::user',
    'Got patron 1'
) or BAIL_OUT('Need Patron1');

# Create a circ session for holds placement.
my $circ_session = $script->session('open-ils.circ');

# Place 5 holds for RECORD_ID for PATRON1. Expect success.
my $request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken,
    {
        hold_type => 'T',
        patronid => $patron1->id(),
        pickup_lib => $patron1->home_ou()
    },
    [RECORD_ID, RECORD_ID, RECORD_ID, RECORD_ID, RECORD_ID]
);
my $success = 0;
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && !ref $result->{result}) {
        $success++;
        push(@holds, $result->{result});
    }
}
$request->finish();
is(
    $success,
    5,
    'Placed 5 title holds for Patron 1'
);

# Place 1 hold for RECORD_ID for PATRON1. Expect HOLD_EXISTS.
$request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken,
    {
        hold_type => 'T',
        patronid => $patron1->id(),
        pickup_lib => $patron1->home_ou()
    },
    [RECORD_ID]
);
my $textcode;
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && ref($result->{result}) eq 'ARRAY') {
        if (grep {$_->{textcode} eq 'HOLD_EXISTS'} @{$result->{result}}) {
            $textcode = 'HOLD_EXISTS';
        }
    }
}
$request->finish();
is(
    $textcode,
    'HOLD_EXISTS',
    'Got HOLD_EXISTS placing 6th title hold for patron 1'
);

# Place 5 holds for METARECORD_ID for PATRON1. Expect success.
$request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken,
    {
        hold_type => 'M',
        patronid => $patron1->id(),
        pickup_lib => $patron1->home_ou()
    },
    [METARECORD_ID, METARECORD_ID, METARECORD_ID, METARECORD_ID, METARECORD_ID]
);
$success = 0;
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && !ref $result->{result}) {
        $success++;
        push(@holds, $result->{result});
    }
}
$request->finish();
is(
    $success,
    5,
    'Placed 5 metarecord holds for Patron 1'
);

# Place 1 hold for METARECORD_ID for PATRON1. Expect HOLD_EXISTS.
$request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken,
    {
        hold_type => 'M',
        patronid => $patron1->id(),
        pickup_lib => $patron1->home_ou()
    },
    [METARECORD_ID]
);
$textcode = '';
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && ref($result->{result}) eq 'ARRAY') {
        if (grep {$_->{textcode} eq 'HOLD_EXISTS'} @{$result->{result}}) {
            $textcode = 'HOLD_EXISTS';
        }
    }
}
$request->finish();
is(
    $textcode,
    'HOLD_EXISTS',
    'Got HOLD_EXISTS placing 6th metarecord hold for patron 1'
);

# Place 5 holds for COPY_ID for PATRON1. Expect 1 success and 4 HOLD_EXISTS.
$request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken,
    {
        hold_type => 'C',
        patronid => $patron1->id(),
        pickup_lib => $patron1->home_ou()
    },
    [COPY_ID, COPY_ID, COPY_ID, COPY_ID, COPY_ID]
);
$success = 0;
$textcode = 0; # Using textcode as int this time.
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && ref($result->{result}) eq 'ARRAY') {
        if (grep {$_->{textcode} eq 'HOLD_EXISTS'} @{$result->{result}}) {
            $textcode++;
        }
    } elsif ($result->{result}) {
        $success++;
        push(@holds, $result->{result});
    }
}
$request->finish();
is(
    $success,
    1,
    'Placed 1 copy hold for patron 1'
);
is(
    $textcode,
    4,
    'Got 4 HOLD_EXISTS on copy holds for patron 1'
);

# Retrieve PATRON2.
my $patron2 = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.fleshed.retrieve_by_barcode',
    $authtoken,
    PATRON2_BARCODE
);
isa_ok(
    ref $patron2,
    'Fieldmapper::actor::user',
    'Got patron 2'
) or BAIL_OUT('Need Patron 2');

# Place 5 holds for RECORD_ID for PATRON2. Expect 1 success and 4 HOLD_EXISTS.
$request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken,
    {
        hold_type => 'T',
        patronid => $patron2->id(),
        pickup_lib => $patron2->home_ou()
    },
    [RECORD_ID, RECORD_ID, RECORD_ID, RECORD_ID, RECORD_ID]
);
$success = 0;
$textcode = 0; # Using textcode as int this time.
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && ref($result->{result}) eq 'ARRAY') {
        if (grep {$_->{textcode} eq 'HOLD_EXISTS'} @{$result->{result}}) {
            $textcode++;
        }
    } elsif ($result->{result}) {
        $success++;
        push(@holds, $result->{result});
    }
}
$request->finish();
is(
    $success,
    1,
    'Placed 1 title hold for patron 2'
);
is(
    $textcode,
    4,
    'Got 4 HOLD_EXISTS on title holds for patron 2'
);

# Place 5 holds for METARECORD_ID for PATRON2. Expect 1 success and 4 HOLD_EXISTS.
$request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken,
    {
        hold_type => 'M',
        patronid => $patron2->id(),
        pickup_lib => $patron2->home_ou()
    },
    [METARECORD_ID, METARECORD_ID, METARECORD_ID, METARECORD_ID, METARECORD_ID]
);
$success = 0;
$textcode = 0; # Using textcode as int this time.
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && ref($result->{result}) eq 'ARRAY') {
        if (grep {$_->{textcode} eq 'HOLD_EXISTS'} @{$result->{result}}) {
            $textcode++;
        }
    } elsif ($result->{result}) {
        $success++;
        push(@holds, $result->{result});
    }
}
$request->finish();
is(
    $success,
    1,
    'Placed 1 metarecord hold for patron 2'
);
is(
    $textcode,
    4,
    'Got 4 HOLD_EXISTS on metarecord holds for patron 2'
);

# Place 5 holds for COPY_ID for PATRON2. Expect 1 success and 4 HOLD_EXISTS.
$request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken,
    {
        hold_type => 'C',
        patronid => $patron2->id(),
        pickup_lib => $patron2->home_ou()
    },
    [COPY_ID, COPY_ID, COPY_ID, COPY_ID, COPY_ID]
);
$success = 0;
$textcode = 0; # Using textcode as int this time.
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && ref($result->{result}) eq 'ARRAY') {
        if (grep {$_->{textcode} eq 'HOLD_EXISTS'} @{$result->{result}}) {
            $textcode++;
        }
    } elsif ($result->{result}) {
        $success++;
        push(@holds, $result->{result});
    }
}
$request->finish();
is(
    $success,
    1,
    'Placed 1 copy hold for patron 2'
);
is(
    $textcode,
    4,
    'Got 4 HOLD_EXISTS on copy holds for patron 2'
);

# Cancel all of the holds placed.
# How many successes we expect.
my $expect = scalar(@holds);
$success = 0;
foreach my $hold (@holds) {
    my $result = $circ_session->request(
        'open-ils.circ.hold.cancel',
        $authtoken,
        $hold,
        5,
        'LP 1694058 perl test'
    )->gather(1);
    if ($result && ! ref $result) {
        $success++;
    }
}
is(
    $success,
    $expect,
    "Cancelled $expect holds"
);

# Reset @holds
@holds = ();

# Test the permission by logging in as patron 1 and placing a title and metarecord hold.

# Login as patron1.
my $patron_auth = $script->authenticate({
    username => $patron1->usrname(),
    password => 'demo123',
    type => 'opac'
});
ok(
    $patron_auth,
    'Logged in as patron 1'
);

# Place 5 holds for RECORD_ID as PATRON1. Expect 1 success and 4 HOLD_EXISTS.
$request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $patron_auth,
    {
        hold_type => 'T',
        patronid => $patron1->id(),
        pickup_lib => $patron1->home_ou()
    },
    [RECORD_ID, RECORD_ID, RECORD_ID, RECORD_ID, RECORD_ID]
);
$success = 0;
$textcode = 0; # Using textcode as int this time.
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && ref($result->{result}) eq 'ARRAY') {
        if (grep {$_->{textcode} eq 'HOLD_EXISTS'} @{$result->{result}}) {
            $textcode++;
        }
    } elsif ($result->{result}) {
        $success++;
        push(@holds, $result->{result});
    }
}
$request->finish();
is(
    $success,
    1,
    'Patron 1 placed 1 title hold'
);
is(
    $textcode,
    4,
    'Patron 1 got 4 HOLD_EXISTS on title holds'
);

# Ditto for metarecord holds:
$request = $circ_session->request(
    'open-ils.circ.holds.test_and_create.batch',
    $patron_auth,
    {
        hold_type => 'T',
        patronid => $patron1->id(),
        pickup_lib => $patron1->home_ou()
    },
    [METARECORD_ID, METARECORD_ID, METARECORD_ID, METARECORD_ID, METARECORD_ID]
);
$success = 0;
$textcode = 0; # Using textcode as int this time.
while (my $response = $request->recv()) {
    my $result = $response->content();
    if ($result->{result} && ref($result->{result}) eq 'ARRAY') {
        if (grep {$_->{textcode} eq 'HOLD_EXISTS'} @{$result->{result}}) {
            $textcode++;
        }
    } elsif ($result->{result}) {
        $success++;
        push(@holds, $result->{result});
    }
}
$request->finish();
is(
    $success,
    1,
    'Patron 1 placed 1 metarecord hold'
);
is(
    $textcode,
    4,
    'Patron 1 got 4 HOLD_EXISTS on metarecord holds'
);

# Cancel the patron-placed holds.
$expect = scalar(@holds);
$success = 0;
foreach my $hold (@holds) {
    my $result = $circ_session->request(
        'open-ils.circ.hold.cancel',
        $patron_auth,
        $hold,
        6,
        'LP 1694058 perl test'
    )->gather(1);
    if ($result && ! ref $result) {
        $success++;
    }
}
is(
    $success,
    $expect,
    "Cancelled $expect patron holds"
);

# Reset @holds
@holds = ();

# Unset OILS_SETTING_MAX_DUPLICATE_HOLDS at BR1.
$setting_value = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $authtoken,
    BR1_ID,
    {OILS_SETTING_MAX_DUPLICATE_HOLDS, undef}
);
ok(
    ! ref $setting_value,
    'circ.holds.max_duplicate_holds unset for BR1'
);

# Logout. Because of a "bug" in Cronscript.pm, we need to log out in the order that we logged in.
$script->logout($authtoken);
$script->logout($patron_auth);
ok(
    ! $script->authtoken,
    'Successfully logged out'
);

