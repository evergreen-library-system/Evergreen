#!perl
use strict; use warnings;

use Test::More tests => 28;
use Data::Dumper;

diag("Test config.standing_penalty.ignore_proximity feature.");

use OpenILS::Utils::TestUtils;
use OpenILS::SIP::Patron;
my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';

use constant WORKSTATION_NAME => 'BR1-test-lp1499123_csp_ignore_proximity.t';
use constant WORKSTATION_LIB => 4;

sub retrieve_staff_chr {
    my $e = shift;
    my $staff_chr = $e->retrieve_config_standing_penalty(25);
    return $staff_chr;
}

sub update_staff_chr {
    my $e = shift;
    my $penalty = shift;
    $e->xact_begin;
    my $r = $e->update_config_standing_penalty($penalty) || $e->event();
    if (ref($r)) {
        $e->rollback();
    } else {
        $e->commit;
    }
    return $r;
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

sub retrieve_copy_by_barcode {
    my $editor = shift;
    my $barcode = shift;
    my $r = $editor->search_asset_copy({barcode => $barcode});
    if (ref($r) eq 'ARRAY' && @$r) {
        return $r->[0];
    }
    return undef;
}

sub apply_staff_chr_to_patron {
    my ($staff, $patron) = @_;
    my $penalty = Fieldmapper::actor::user_standing_penalty->new();
    $penalty->standing_penalty(25);
    $penalty->usr($patron->id());
    $penalty->set_date('now');
    $penalty->staff($staff->id());
    $penalty->org_unit(1); # Consortium-wide.
    #$penalty->note('LP 1499123 csp.ignore_proximity test');
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

sub remove_staff_chr_from_patron {
    my $penalty = shift;
    return $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.note.remove',
        $script->authtoken,
        $penalty
    );
}

sub checkout_permit_test {
    my $patron = shift;
    my $copy_barcode = shift;
    my $r = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.checkout.permit',
        $script->authtoken,
        {
            patron => $patron->id(),
            barcode => $copy_barcode
        }
    );
    if (ref($r) eq 'HASH' && $r->{textcode} eq 'SUCCESS') {
        return 1;
    }
    return 0;
}

sub copy_hold_permit_test {
    my $editor = shift;
    my $patron = shift;
    my $copy_barcode = shift;
    my $copy = retrieve_copy_by_barcode($editor, $copy_barcode);
    if ($copy) {
        my $r = $apputils->simplereq(
            'open-ils.circ',
            'open-ils.circ.title_hold.is_possible',
            $script->authtoken,
            {
                patronid => $patron->id(),
                pickup_lib => 4,
                copy_id => $copy->id(),
                hold_type => 'C'
            }
        );
        if (ref($r) && defined $r->{success}) {
            return $r->{success};
        }
    }
    return undef;
}

sub patron_sip_test {
    my $patron_id = shift;
    my $patron = OpenILS::SIP::Patron->new(usr => $patron_id, authtoken => $script->authtoken);
    return scalar(@{$patron->{user}->standing_penalties()});
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

# We retrieve STAFF_CHR block and check that it has an undefined
# ignore_proximity.
my $staff_chr = retrieve_staff_chr($editor);
isa_ok($staff_chr, 'Fieldmapper::config::standing_penalty', 'STAFF_CHR');
is($staff_chr->name, 'STAFF_CHR', 'Penalty name is STAFF_CHR');
is($staff_chr->ignore_proximity, undef, 'STAFF_CHR ignore_proximity is undefined');

# We set the ignore_proximity to 0.
$staff_chr->ignore_proximity(0);
ok(! ref update_staff_chr($editor, $staff_chr), 'Update of STAFF_CHR');

# We need a patron with no penalties to test holds and circulation.
my $patron = retrieve_user_by_barcode("99999350419");
isa_ok($patron, 'Fieldmapper::actor::user', 'Patron');

# Patron should have no penalties.
ok(! scalar(@{$patron->standing_penalties()}), 'Patron has no penalties');

# Add the STAFF_CHR to the patron
my $penalty = apply_staff_chr_to_patron($staff, $patron);
ok(ref $penalty, 'Added STAFF_CHR to patron');
is(patron_sip_test($patron->id()), 0, 'SIP says patron has no penalties');

# See if we can place a hold on a copy owned by BR1.
is(copy_hold_permit_test($editor, $patron, "CONC4300036"), 1, 'Can place hold on copy from BR1');
# We should not be able to place a  hold on a copy owned by a different branch.
is(copy_hold_permit_test($editor, $patron, "CONC51000636"), 0, 'Cannot place hold on copy from BR2');

# See if we can check out a copy owned by branch 4 out to the patron.
# This should succeed.
ok(checkout_permit_test($patron, "CONC4300036"), 'Can checkout copy from BR1');

# We should not be able to checkout a copy owned by a different branch.
ok(!checkout_permit_test($patron, "CONC51000636"), 'Cannot checkout copy from BR2');

# We reset the ignore_proximity of STAFF_CHR.
$staff_chr->clear_ignore_proximity();
ok(! ref update_staff_chr($editor, $staff_chr), 'Reset of STAFF_CHR');
is(patron_sip_test($patron->id()), 1, 'SIP says patron has one penalty');

# See if we can place a hold on a copy owned by BR1.
is(copy_hold_permit_test($editor, $patron, "CONC4300036"), 0, 'Cannot place hold on copy from BR1');
# We should not be able to place a  hold on a copy owned by a different branch.
is(copy_hold_permit_test($editor, $patron, "CONC51000636"), 0, 'Cannot place hold on copy from BR2');

# See if we can check out a copy owned by branch 4 out to the patron.
# This should succeed.
ok(!checkout_permit_test($patron, "CONC4300036"), 'Cannot checkout copy from BR1');

# We should not be able to checkout a copy owned by a different branch.
ok(!checkout_permit_test($patron, "CONC51000636"), 'Cannot checkout copy from BR2');

# We remove the STAFF_CHR from our test patron.
my $r = remove_staff_chr_from_patron($penalty);
ok( ! ref $r, 'STAFF_CHR removed from patron');

# Do the checks again, all should pass.
is(patron_sip_test($patron->id()), 0, 'SIP says patron has no penalties');

# See if we can place a hold on a copy owned by BR1.
is(copy_hold_permit_test($editor, $patron, "CONC4300036"), 1, 'Can place hold on copy from BR1');
# We should now be able to place a  hold on a copy owned by a different branch.
is(copy_hold_permit_test($editor, $patron, "CONC51000636"), 1, 'Can place hold on copy from BR2');

# See if we can check out a copy owned by branch 4 out to the patron.
# This should succeed.
ok(checkout_permit_test($patron, "CONC4300036"), 'Can checkout copy from BR1');

# We should not be able to checkout a copy owned by a different branch.
ok(checkout_permit_test($patron, "CONC51000636"), 'Can checkout copy from BR2');

$script->logout();
