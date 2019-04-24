#!perl

use Test::More tests => 20;

diag("Test fine generation on checkin against the admin user.");

use constant WORKSTATION_NAME => 'BR4-test-03-overdue-circ.t';
use constant WORKSTATION_LIB => 7;
use constant ITEM_BARCODE => 'CONC71000345';
use constant ITEM_ID => 810;

use strict; use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();

use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Utils::DateTime qw/clean_ISO8601/;

our $apputils = 'OpenILS::Application::AppUtils';

#----------------------------------------------------------------
# The tests...  assumes stock sample data
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

my $xact_start = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($circ->xact_start));
my $due_date = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($circ->due_date));

# Rewrite history; technically we should rewrite status_changed_item on the copy as well, but, meh...
$circ->xact_start( $xact_start->subtract( days => 20 )->iso8601() );
$circ->due_date( $due_date->subtract( days => 20 )->iso8601() );

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
            13,
            'Thirteen bills associated with circulation'
        );
    }
}


$script->logout();


