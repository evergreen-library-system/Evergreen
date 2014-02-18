#!perl

use Test::More tests => 23;

diag("Test fine generation with closed date on checkin against the admin user.");

use constant WORKSTATION_NAME => 'BR4-test-04-overdue-with-closed-dates.t';
use constant WORKSTATION_LIB => 7;
use constant ITEM_BARCODE => 'CONC72000345';
use constant ITEM_ID => 1310;

use strict; use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();

use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/cleanse_ISO8601/;

our $apputils   = "OpenILS::Application::AppUtils";

sub create_closed_date {
    my $ten_days = OpenSRF::Utils->interval_to_seconds('240 h 0 m 0 s');
    my $almost_twenty_four_hours = OpenSRF::Utils->interval_to_seconds('23 h 59 m 59 s');
    #$circ->due_date( $apputils->epoch2ISO8601($due_date - $twenty_days) );

    my $aoucd = Fieldmapper::actor::org_unit::closed_date->new;
    $aoucd->org_unit(WORKSTATION_LIB);
    $aoucd->reason('04-overdue_with_closed_dates.t');
    $aoucd->close_start(
        $apputils->epoch2ISO8601(
            DateTime->today()->epoch() - $ten_days
        )
    );
    $aoucd->close_end(
        $apputils->epoch2ISO8601(
            DateTime->today()->epoch() - $ten_days + $almost_twenty_four_hours
        )
    );
    my $resp = $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.org_unit.closed.create',
        $script->authtoken, $aoucd);
    return $resp;
}

# returns "1" on success, event on error
sub update_closed_date {
    my $aoucd = shift;
    $aoucd->reason($aoucd->reason . ' modified');
    return $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.org_unit.closed.update',
        $script->authtoken, $aoucd);
}

sub delete_closed_date {
    my $aoucd = shift;
    my $resp = $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.org_unit.closed.delete',
        $script->authtoken, ref $aoucd ? $aoucd->id : $aoucd );
    return $resp;
}

#----------------------------------------------------------------
# The tests...  assumes stock sample data, full-auto install by
# eg_wheezy_installer.sh, etc.
#----------------------------------------------------------------

my $storage_ses = $script->session('open-ils.storage');
my $circ_ses = $script->session('open-ils.circ');
my $cstore_ses = $script->session('open-ils.cstore');

my $user_req = $storage_ses->request('open-ils.storage.direct.actor.user.retrieve', 1);
if (my $user_resp = $user_req->recv) {
    if (my $user = $user_resp->content) {
        is(
            ref $user,
            'Fieldmapper::actor::user',
            'open-ils.storage.direct.actor.user.retrieve returned aou object'
        );
        is(
            $user->usrname,
            'admin',
            'User with id = 1 is admin user'
        );
    }
}

my $item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', ITEM_ID);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->barcode,
            ITEM_BARCODE,
            'Item with id = ' . ITEM_ID . ' has barcode ' . ITEM_BARCODE
        );
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . ITEM_ID . ' has status of Reshelving or Available'
        );
    }
}

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});
ok(
    $script->authtoken,
    'Have an authtoken'
);
my $ws = $script->register_workstation(WORKSTATION_NAME,WORKSTATION_LIB);
ok(
    ! ref $ws,
    'Registered a new workstation'
);

$script->logout();
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff',
    workstation => WORKSTATION_NAME});
ok(
    $script->authtoken,
    'Have an authtoken associated with the workstation'
);

my $closed_date_obj = create_closed_date();
is(
    ref $closed_date_obj,
    'Fieldmapper::actor::org_unit::closed_date',
    'Created a closed date for 10 days ago'
);

is(
    update_closed_date($closed_date_obj),
    '1',
    'Updated closed date reason'
);

my $checkout_resp = $script->do_checkout({
    patron => 1,
    barcode => ITEM_BARCODE});
is(
    ref $checkout_resp,
    'HASH',
    'Checkout request returned a HASH'
);
is(
    $checkout_resp->{ilsevent},
    0,
    'Checkout returned a SUCCESS event'
);
ok(
    ref $checkout_resp->{payload},
    'Checkout response object has payload object'
);
ok(
    ref $checkout_resp->{payload}->{circ},
    'Payload object has circ object'
);
is(
    $checkout_resp->{payload}->{circ}->duration,
    '7 days',
    'Circ objection has loan duration of "7 days"'
);

my $circ = $checkout_resp->{payload}->{circ};

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', ITEM_ID);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            $item->status,
            1,
            'Item with id = ' . ITEM_ID . ' has status of Checked Out after fresh Storage request'
        );
    }
}

my $bill_req = $circ_ses->request(
    'open-ils.circ.money.billing.retrieve.all',
    $script->authtoken,
    $circ->id
);
if (my $bill_resp = $bill_req->recv) {
    if (my $bills = $bill_resp->content) {
        is(
            scalar( @{ $bills } ),
            0,
            'Zero bills associated with circulation'
        );
    }
}

my $xact_start = DateTime::Format::ISO8601->parse_datetime(cleanse_ISO8601($circ->xact_start))->epoch;
my $due_date = DateTime::Format::ISO8601->parse_datetime(cleanse_ISO8601($circ->due_date))->epoch;
my $twenty_days = OpenSRF::Utils->interval_to_seconds('480 h 0 m 0 s');

# Rewrite history; technically we should rewrite status_changed_item on the copy as well, but, meh...
$circ->xact_start( $apputils->epoch2ISO8601($xact_start - $twenty_days) );
$circ->due_date( $apputils->epoch2ISO8601($due_date - $twenty_days) );

$cstore_ses->connect; # need stateful connection
my $xact = $cstore_ses->request('open-ils.cstore.transaction.begin')->gather(1);
my $update_req = $cstore_ses->request(
    'open-ils.cstore.direct.action.circulation.update',
    $circ
);
if (my $update_resp = $update_req->gather(1)) {
    pass(
        'rewrote circ to have happened 20 days ago'
    );
} else {
    fail(
        'rewrote circ to have happened 20 days ago'
    );
}
$cstore_ses->request('open-ils.cstore.transaction.commit')->gather(1);

########

my $checkin_resp = $script->do_checkin({
    barcode => ITEM_BARCODE});
is(
    ref $checkin_resp,
    'HASH',
    'Checkin request returned a HASH'
);
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', ITEM_ID);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . ITEM_ID . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

$bill_req = $circ_ses->request(
    'open-ils.circ.money.billing.retrieve.all',
    $script->authtoken,
    $circ->id
);
if (my $bill_resp = $bill_req->recv) {
    if (my $bills = $bill_resp->content) {
        is(
            scalar( @{ $bills } ),
            12,
            'Twelve bills associated with circulation (instead of 13, thanks to closed date)'
        );
    }
}

my $tmp = delete_closed_date($closed_date_obj);
is($tmp,    1,  'Removed closed date');

$script->logout();


