#!perl
use strict;
use warnings;

use Test::More tests => 30;

# This test includes much code copied or adapted from Jason Stephenson's tests
# in 14-lp1499123_csp_ignore_proximity.t

diag("Test bugfix for lp1592891 - SIP2 failures with standing penalties.");

use OpenILS::Const qw/:const/;
use OpenILS::Utils::TestUtils;
use OpenILS::SIP::Patron;
my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';

use constant WORKSTATION_NAME => 'BR1-test-lp1592891_sip_standing_penalties.t';
use constant WORKSTATION_LIB => 4;

sub retrieve_penalty {
    my $e = shift;
    my $penalty = shift;
    my $csp = $e->retrieve_config_standing_penalty($penalty);
    return $csp;
}

sub retrieve_user_by_barcode {
    my $barcode = shift;
    return $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.fleshed.retrieve_by_barcode',
        $script->authtoken,
        $barcode
    );
}

sub apply_penalty_to_patron {
    my ($staff, $patron, $penalty_id) = @_;
    my $penalty = Fieldmapper::actor::user_standing_penalty->new();
    $penalty->standing_penalty($penalty_id);
    $penalty->usr($patron->id());
    $penalty->set_date('now');
    $penalty->staff($staff->id());
    $penalty->org_unit(1); # Consortium-wide.
    #$penalty->note('LP 1592891 SIP standing penalties test');
    my $r = $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.note.apply',
        $script->authtoken,
        $penalty
    );
    if (ref($r)) {
        undef($penalty);
    } else {
        $penalty->id($r);
    }
    return $penalty;
}

sub remove_penalty_from_patron {
    my $penalty = shift;
    return $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.note.remove',
        $script->authtoken,
        $penalty
    );
}

sub patron_sip_test {
    my $patron_id = shift;
    my $patron = OpenILS::SIP::Patron->new(usr => $patron_id, authtoken => $script->authtoken);
    return scalar(@{$patron->{user}->standing_penalties()});
}

sub patron_sip_too_many_overdue_test {
    my $patron_id = shift;
    my $patron = OpenILS::SIP::Patron->new(usr => $patron_id, authtoken => $script->authtoken);
    my $rv;
    eval { $rv = $patron->too_many_overdue };
    if ($@) {
        diag('$patron->too_many_overdue crashed: ' . $@);
        return;
    } else {
        return $rv;
    }
}

sub patron_sip_excessive_fines_test {
    my $patron_id = shift;
    my $patron = OpenILS::SIP::Patron->new(usr => $patron_id, authtoken => $script->authtoken);
    my $rv;
    eval { $rv = $patron->excessive_fines };
    if ($@) {
        diag('$patron->excessive_fines crashed: ' . $@);
        return;
    } else {
        return $rv;
    }
}

# In concerto, we need to register a workstation.
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff',
});
ok($script->authtoken, 'Initial Login');

SKIP: {
    my $ws = $script->find_workstation(WORKSTATION_NAME, WORKSTATION_LIB);
    skip 'Workstation exists', 1 if ($ws);
    $ws = $script->register_workstation(WORKSTATION_NAME, WORKSTATION_LIB) unless ($ws);
    ok(! ref $ws, 'Registered a new workstation');
}

$script->logout();
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff',
    workstation => WORKSTATION_NAME
});
ok($script->authtoken, 'Login with workstaion');

# Get a CStoreEditor for later use.
my $editor = $script->editor(authtoken=>$script->authtoken);
my $staff = $editor->checkauth();
ok(ref($staff), 'Got a staff user');

# We retrieve STAFF_CHR penalty and check that it has an undefined
# ignore_proximity.
my $staff_chr = retrieve_penalty($editor, 25);
isa_ok($staff_chr, 'Fieldmapper::config::standing_penalty', 'STAFF_CHR');
is($staff_chr->name, 'STAFF_CHR', 'Penalty name is STAFF_CHR');
is($staff_chr->ignore_proximity, undef, 'STAFF_CHR ignore_proximity is undefined');

# We retrieve OILS_PENALTY_PATRON_EXCEEDS_FINES penalty and check that it has an undefined
# ignore_proximity.
my $csp_fines = retrieve_penalty($editor, OILS_PENALTY_PATRON_EXCEEDS_FINES);
isa_ok($csp_fines, 'Fieldmapper::config::standing_penalty', 'PATRON_EXCEEDS_FINES');
is($csp_fines->name, 'PATRON_EXCEEDS_FINES', 'Penalty name is PATRON_EXCEEDS_FINES');
is($csp_fines->ignore_proximity, undef, 'PATRON_EXCEEDS_FINES ignore_proximity is undefined');

# We retrieve STAFF_CHR penalty and check that it has an undefined
# ignore_proximity.
my $csp_overdues = retrieve_penalty($editor, OILS_PENALTY_PATRON_EXCEEDS_OVERDUE_COUNT);
isa_ok($csp_overdues, 'Fieldmapper::config::standing_penalty', 'PATRON_EXCEEDS_OVERDUE_COUNT');
is($csp_overdues->name, 'PATRON_EXCEEDS_OVERDUE_COUNT', 'Penalty name is PATRON_EXCEEDS_OVERDUE_COUNT');
is($csp_overdues->ignore_proximity, undef, 'PATRON_EXCEEDS_OVERDUE_COUNT ignore_proximity is undefined');

# We need a patron with no penalties to test holds and circulation.
my $patron = retrieve_user_by_barcode("99999350419");
isa_ok($patron, 'Fieldmapper::actor::user', 'Patron');

# Patron should have no penalties.
ok(! scalar(@{$patron->standing_penalties()}), 'Patron has no penalties');
is(patron_sip_test($patron->id()), 0, 'SIP says patron has no penalties');
is(patron_sip_too_many_overdue_test($patron->id()), 0, 'SIP says patron does not have too many overdues');
is(patron_sip_excessive_fines_test($patron->id()), 0, 'SIP says patron does not have excessive fines');

# Add STAFF_CHR penalty to the patron
my $penalty = apply_penalty_to_patron($staff, $patron, 25);
ok(ref $penalty, 'Added STAFF_CHR penalty to patron');
is(patron_sip_test($patron->id()), 1, 'SIP says patron has one penalty');

# Add PATRON_EXCEEDS_FINES penalty to the patron
my $fines_penalty = apply_penalty_to_patron($staff, $patron, OILS_PENALTY_PATRON_EXCEEDS_FINES);
ok(ref $fines_penalty, 'Added PATRON_EXCEEDS_FINES penalty to patron');
is(patron_sip_test($patron->id()), 2, 'SIP says patron has two penalties');
is(patron_sip_excessive_fines_test($patron->id()), 1, 'SIP says patron has excessive fines');

# Add PATRON_EXCEEDS_OVERDUE_COUNT penalty to the patron
my $overdues_penalty = apply_penalty_to_patron($staff, $patron, OILS_PENALTY_PATRON_EXCEEDS_OVERDUE_COUNT);
ok(ref $overdues_penalty, 'Added PATRON_EXCEEDS_OVERDUE_COUNT penalty to patron');
is(patron_sip_test($patron->id()), 3, 'SIP says patron has three penalties');
is(patron_sip_excessive_fines_test($patron->id()), 1, 'SIP says patron has excessive fines');
is(patron_sip_too_many_overdue_test($patron->id()), 1, 'SIP says patron has too many overdues');

# We remove the penalties from our test patron.
my $r = remove_penalty_from_patron($penalty);
ok( ! ref $r, 'STAFF_CHR removed from patron');
my $r_fines = remove_penalty_from_patron($fines_penalty);
ok( ! ref $r_fines, 'PATRON_EXCEEDS_FINES removed from patron');
my $r_overdues = remove_penalty_from_patron($overdues_penalty);
ok( ! ref $r_overdues, 'PATRON_EXCEEDS_OVERDUE_COUNT removed from patron');

$script->logout();
