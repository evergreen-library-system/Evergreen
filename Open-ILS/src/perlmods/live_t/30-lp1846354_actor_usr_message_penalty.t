#!perl
use strict; use warnings;

use Test::More tests => 12;
use Data::Dumper;

diag("Test actor.usr_message_penalty feature.");

use OpenILS::Utils::TestUtils;
use OpenILS::SIP::Patron;
my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';

use constant WORKSTATION_NAME => 'BR1-test-30-lp1846354_actor_usr_message_penalty.t';
use constant WORKSTATION_LIB => 4;

sub retrieve_user_by_barcode {
    my $barcode = shift;
    return $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.fleshed.retrieve_by_barcode',
        $script->authtoken,
        $barcode
    );
}

sub retrieve_user_messages {
    my $patron = shift;
    return $apputils->simplereq(
        'open-ils.pcrud',
        'open-ils.pcrud.search.aum.atomic',
        $script->authtoken,
        { 'usr' => $patron->id() }
    );
}

sub apply_staff_chr_to_patron_with_msg {
    my $patron = shift;
    my $penalty = Fieldmapper::actor::user_standing_penalty->new();
    $penalty->standing_penalty(25);
    $penalty->usr($patron->id());
    $penalty->set_date('now');
    $penalty->staff(1); # admin
    $penalty->org_unit(1); # Consortium-wide.
    my $msg = {
        pub => 't',
        title => 'lp1846354 test title',
        message => 'lp1846354 test message'
    };
    my $r = $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.note.apply',
        $script->authtoken,
        $penalty,
        $msg
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

my $patron = retrieve_user_by_barcode("99999350419");
isa_ok($patron, 'Fieldmapper::actor::user', 'Patron');

# Patron should have no penalties.
ok(! scalar(@{$patron->standing_penalties()}), 'Patron has no penalties');

# Patron should have no user messages
my $user_messages = retrieve_user_messages($patron);
ok(! scalar(@{$user_messages}), 'Patron has no user messages');

# Add the STAFF_CHR to the patron
my $penalty = apply_staff_chr_to_patron_with_msg($patron);
ok(ref $penalty, 'Added STAFF_CHR to patron');

# Patron should have one user message
$user_messages = retrieve_user_messages($patron);
ok(scalar(@{$user_messages} == 1), 'Patron has a user message');

# It should be public/patron-visible
ok(@{$user_messages}[0]->pub() eq 't', 'User message pub flag is true');

# It should be flagged as not deleted
ok(@{$user_messages}[0]->deleted() eq 'f', 'User message is not flagged deleted');

# We remove the STAFF_CHR from our test patron.
my $r = remove_staff_chr_from_patron($penalty);
ok( ! ref $r, 'STAFF_CHR removed from patron');

# It should be flagged as not deleted
$user_messages = retrieve_user_messages($patron);
ok(@{$user_messages}[0]->deleted() eq 'f', 'User message is not flagged deleted');
# worth noting that the Remove Note action in the staff client will delete both
# the penalty and its user message

$script->logout();
