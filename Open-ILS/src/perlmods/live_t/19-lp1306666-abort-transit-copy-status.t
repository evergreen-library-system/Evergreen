#!perl
use strict; use warnings;
use Test::More tests => 26;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);

diag("Test LP 1306666 abort transit copy status fix.");

my $script = OpenILS::Utils::TestUtils->new();
my $apputils = 'OpenILS::Application::AppUtils';

use constant {
    BR1_WORKSTATION => 'BR1-test-lp1306666-abort-transit-copyt-status.t',
    BR1_ID => 4,
    BR3_WORKSTATION => 'BR3-test-lp1306666-abort-transit-copyt-status.t',
    BR3_ID => 6,
    PBARCODE => '99999378730',
    CBARCODE => 'CONC4000036'
};

# Store authtokens
my @authtoken = ();

# Login as staff at BR1
$authtoken[0] = $script->authenticate({
    username => 'br1vcampbell',
    password => 'demo123',
    type => 'staff'
});

# Register workstation at BR1.
unless ($script->find_workstation(BR1_WORKSTATION, BR1_ID)) {
    $script->register_workstation(BR1_WORKSTATION, BR1_ID);
}

# Logout of BR1.
$script->logout($authtoken[0]);

# Login as staff at BR1 using workstation.
$authtoken[0] = $script->authenticate({
    username => 'br1vcampbell',
    password => 'demo123',
    type => 'staff',
    workstation => BR1_WORKSTATION
});

# Login as staff at BR3
$authtoken[1] = $script->authenticate({
    username => 'br3sforbes',
    password => 'demo123',
    type => 'staff'
});

# Register workstation at BR3.
unless ($script->find_workstation(BR3_WORKSTATION, BR3_ID)) {
    $script->register_workstation(BR3_WORKSTATION, BR3_ID);
}

# Logout of BR3.
$script->logout($authtoken[1]);

# Login as staff at BR3 using workstation.
$authtoken[1] = $script->authenticate({
    username => 'br3sforbes',
    password => 'demo123',
    type => 'staff',
    workstation => BR3_WORKSTATION
});

# Retrieve copy at BR1
my $copy = $apputils->simplereq(
    'open-ils.search',
    'open-ils.search.asset.copy.find_by_barcode',
    CBARCODE
);

# Check that copy exists.
isa_ok(ref($copy), 'Fieldmapper::asset::copy', 'Got copy') or BAIL_OUT('Need copy');

# Retrieve patron at BR3
my $patron = $apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.fleshed.retrieve_by_barcode',
    $authtoken[1],
    PBARCODE
);

# Check that patron exists.
isa_ok(ref($patron), 'Fieldmapper::actor::user', 'Got patron') or BAIL_OUT('Need patron');

# Place copy hold for patron pickup at BR3.
my $hold = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken[1],
    {
        hold_type => 'C',
        patronid => $patron->id(),
        pickup_lib => BR3_ID
    },
    [$copy->id()]
);
if (ref($hold->{result})) {
    my $event = (ref($hold->{result}) eq 'ARRAY') ? $hold->{result}->[0] : $hold->{result};
    if ($event->{textcode} eq 'HOLD_EXISTS') {
        my $target = $hold->{target};
        $hold = $apputils->simplereq(
            'open-ils.pcrud',
            'open-ils.pcrud.search.ahr',
            $authtoken[1],
            {target => $target, usr => $patron->id(), fulfillment_time => undef, cancel_time => undef}
        );
    } else {
        BAIL_OUT('Cannot place hold');
    }
} else {
    $hold = $apputils->simplereq(
        'open-ils.pcrud',
        'open-ils.pcrud.retrieve.ahr',
        $authtoken[1],
        $hold->{result}
    );
}

# Check that hold exists.
isa_ok(ref($hold), 'Fieldmapper::action::hold_request', 'Got hold') or BAIL_OUT('Need hold');

# Check copy in at BR1
my $checkin = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.checkin',
    $authtoken[0],
    {barcode => CBARCODE}
);
subtest 'Got ROUTE_ITEM event 1' => sub {
    plan tests => 3;
    is(ref($checkin), 'HASH', 'Got event');
    is($checkin->{textcode}, 'ROUTE_ITEM', 'Route item event');
    is($checkin->{org}, BR3_ID, 'ROUTE_ITEM event destination');
};

# Check copy transit.
my $transit = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.ahtc',
    $authtoken[0],
    {target_copy => $copy->id(), hold => $hold->id(), dest_recv_time => undef}
);
subtest 'Got hold transit 1' => sub {
    plan tests => 4;
    isa_ok(ref($transit), 'Fieldmapper::action::hold_transit_copy', 'Got hold transit copy');
    is($transit->dest(), BR3_ID, 'Transit destination');
    is($transit->source(), BR1_ID, 'Transit source');
    is($transit->copy_status(), OILS_COPY_STATUS_ON_HOLDS_SHELF, 'Transit copy status');
};

# Check copy status.
$copy = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken[0],
    $copy->id()
);
is($copy->status(), OILS_COPY_STATUS_IN_TRANSIT, 'Copy in transit');

# Abort the transit.
my $abort = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.transit.abort',
    $authtoken[0],
    {transitid => $transit->id()}
);
is($abort, 1, 'Transit aborted');

# Check copy status.
$copy = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken[0],
    $copy->id()
);
is($copy->status(), OILS_COPY_STATUS_CANCELED_TRANSIT, 'Copy in Canceled Transit status');

# Check copy in at BR1
$checkin = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.checkin',
    $authtoken[0],
    {barcode => CBARCODE}
);
subtest 'Got ROUTE_ITEM event 2' => sub {
    plan tests => 3;
    is(ref($checkin), 'HASH', 'Got event');
    is($checkin->{textcode}, 'ROUTE_ITEM', 'Route item event');
    is($checkin->{org}, BR3_ID, 'ROUTE_ITEM event destination');
};

# Check copy transit.
$transit = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.ahtc',
    $authtoken[0],
    {target_copy => $copy->id(), hold => $hold->id(), dest_recv_time => undef}
);
subtest 'Got hold transit 2' => sub {
    plan tests => 4;
    isa_ok(ref($transit), 'Fieldmapper::action::hold_transit_copy', 'Got hold transit copy');
    is($transit->dest(), BR3_ID, 'Transit destination');
    is($transit->source(), BR1_ID, 'Transit source');
    is($transit->copy_status(), OILS_COPY_STATUS_ON_HOLDS_SHELF, 'Transit copy status');
};

# Check copy status.
$copy = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken[0],
    $copy->id()
);
is($copy->status(), OILS_COPY_STATUS_IN_TRANSIT, 'Copy in transit 2');

# Check copy in at BR3.
$checkin = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.checkin',
    $authtoken[1],
    {barcode => CBARCODE}
);
subtest 'Checkin at destination' => sub{
    plan tests => 3;
    is(ref($checkin), 'HASH', 'Got event');
    is($checkin->{textcode}, 'SUCCESS', 'Event was successful');
    is($checkin->{ishold}, 1, 'Check In filled hold');
};

# Check hold is on shelf.
$hold = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.ahr',
    $authtoken[1],
    $hold->id()
);
ok(defined($hold->shelf_time()), 'Hold has shelf time');

# Check copy status.
$copy = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken[1],
    $copy->id()
);
is($copy->status(), OILS_COPY_STATUS_ON_HOLDS_SHELF, 'Copy on holds shelf');

# Check copy out to patron at BR3.
my $checkout = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.checkout.full',
    $authtoken[1],
    {copy_id => $copy->id(), patron_id => $patron->id()}
);
subtest 'Checkout to patron' => sub {
    plan tests => 2;
    is(ref($checkout), 'HASH', 'Got checkout event');
    is($checkout->{textcode}, 'SUCCESS', 'Checkout succeeded');
};

# Check the hold is fulfilled.
$hold = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.ahr',
    $authtoken[1],
    $hold->id()
);
ok(defined($hold->fulfillment_time()), 'Hold was fulfilled');

# Check copy status.
$copy = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken[1],
    $copy->id()
);
is($copy->status(), OILS_COPY_STATUS_CHECKED_OUT, 'Copy is checked out');

# Make a transit from BR3 to BR1 for the copy.
# We make the transit with pcrud, because
# open-ils.circ.copy_transit.create changes the copy status.
my $new_transit = Fieldmapper::action::transit_copy->new();
$new_transit->source(BR3_ID);
$new_transit->dest(BR1_ID);
$new_transit->target_copy($copy->id());
$new_transit->copy_status(OILS_COPY_STATUS_RESHELVING);
$new_transit->source_send_time('now');
my $pcrud_ses = $script->session('open-ils.pcrud');
$pcrud_ses->connect();
my $xact = $pcrud_ses->request(
    'open-ils.pcrud.transaction.begin',
    $authtoken[1]
)->gather(1);
$transit = $pcrud_ses->request(
    'open-ils.pcrud.create.atc',
    $authtoken[1],
    $new_transit
)->gather(1);
$pcrud_ses->request(
    'open-ils.pcrud.transaction.commit',
    $authtoken[1]
)->gather(1);
$pcrud_ses->disconnect();
undef($pcrud_ses);
isa_ok(ref($transit), 'Fieldmapper::action::transit_copy', 'Transit created');

# Check the transit.
$transit = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.atc',
    $authtoken[1],
    {target_copy => $copy->id(), source => BR3_ID, dest => BR1_ID, dest_recv_time => undef}
);
subtest 'Got transit 1' => sub {
    plan tests => 4;
    isa_ok(ref($transit), 'Fieldmapper::action::transit_copy', 'Got transit copy');
    is($transit->dest(), BR1_ID, 'Transit destination');
    is($transit->source(), BR3_ID, 'Transit source');
    is($transit->copy_status(), OILS_COPY_STATUS_RESHELVING, 'Transit copy status');
};

# Abort the transit.
$abort = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.transit.abort',
    $authtoken[1],
    {transitid => $transit->id()}
);
is($abort, 1, 'Transit 1 aborted');

# Check copy status.
$copy = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken[1],
    $copy->id()
);
is($copy->status(), OILS_COPY_STATUS_CHECKED_OUT, 'Copy is checked out after transit abort');

# Check copy in at BR3.
$checkin = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.checkin',
    $authtoken[1],
    {barcode => CBARCODE}
);
subtest 'Check in after circulation' => sub{
    plan tests => 3;
    is(ref($checkin), 'HASH', 'Got event');
    is($checkin->{textcode}, 'ROUTE_ITEM', 'Route item event');
    is($checkin->{org}, BR1_ID, 'ROUTE_ITEM event destination');
};

# Check for transit.
$transit = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.atc',
    $authtoken[1],
    {target_copy => $copy->id(), source => BR3_ID, dest => BR1_ID, dest_recv_time => undef}
);
subtest 'Got transit after check in' => sub {
    plan tests => 4;
    isa_ok(ref($transit), 'Fieldmapper::action::transit_copy', 'Got transit copy');
    is($transit->dest(), BR1_ID, 'Transit destination');
    is($transit->source(), BR3_ID, 'Transit source');
    is($transit->copy_status(), OILS_COPY_STATUS_RESHELVING, 'Transit copy status');
};

# Check copy status.
$copy = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken[1],
    $copy->id()
);
is($copy->status(), OILS_COPY_STATUS_IN_TRANSIT, 'Copy in transit after check in');

# Abort the transit.
$abort = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.transit.abort',
    $authtoken[0],
    {transitid => $transit->id()}
);
is($abort, 1, 'Transit aborted');

# Check copy status.
$copy = $apputils->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.retrieve.acp',
    $authtoken[0],
    $copy->id()
);
is($copy->status(), OILS_COPY_STATUS_CANCELED_TRANSIT, 'Copy is in Canceled Transit status');

# Logout at BR1.
$script->logout($authtoken[0]);

# Logout at BR3.
$script->logout($authtoken[1]);
