#!perl

use Test::More tests => 14;

diag("Test circulation of item CONC70000345 against the admin user.");

use constant WORKSTATION_NAME => 'BR4-test-02-simple-circ.t';
use constant WORKSTATION_LIB => 7;
use constant ITEM_BARCODE => 'CONC70000345';
use constant ITEM_ID => 310;

use strict; use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();

#----------------------------------------------------------------
# The tests...  assumes stock sample data
#----------------------------------------------------------------

my $storage_ses = $script->session('open-ils.storage');

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
   
$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', 310);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            $item->status,
            1,
            'Item with id = ' . ITEM_ID . ' has status of Checked Out after fresh Storage request'
        );
    }
}

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

$script->logout();

