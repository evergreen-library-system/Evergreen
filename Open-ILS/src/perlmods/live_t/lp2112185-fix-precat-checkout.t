#!perl
use strict; use warnings;
use Test::More tests => 7;
use OpenILS::Utils::TestUtils;

diag 'LP2112185: Precat items must be able to check out multiple times';

use constant WORKSTATION_NAME => 'BR4-test-lp2112185-fix-precat-checkout.t';
use constant WORKSTATION_LIB => 7; # BR4
use constant BR4_PATRON_ID => 14; # Robert Wade
use constant ITEM_BARCODE => 'μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος'; # This barcode should not exist in the test data hahaha

my $script = OpenILS::Utils::TestUtils->new;
$script->bootstrap;

my $authtoken = $script->authenticate({
    username=>'admin',
    password=>'demo123',
    type=>'staff'
});
ok(
    $script->authtoken,
    'Have an authtoken'
);

my $ws = $script->find_or_register_workstation(WORKSTATION_NAME, WORKSTATION_LIB);
ok(
    ! ref $ws,
    'Found or registered workstation'
);

# Login again, this time with the appropriate workstation
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff',
    workstation => WORKSTATION_NAME
});

my $checkout_resp = $script->do_checkout({
    patron => BR4_PATRON_ID,
    barcode => ITEM_BARCODE
});
is $checkout_resp->{textcode},
    'ITEM_NOT_CATALOGED',
    'It tells you that the item is not cataloged';


$checkout_resp = $script->do_checkout({
    patron => BR4_PATRON_ID,
    barcode => ITEM_BARCODE,
    dummy_title => 'my title',
    precat => 1
});
is $checkout_resp->{textcode},
    'SUCCESS',
    'It can check out a precat if you pass precat => 1';

my $checkin_resp = $script->do_checkin({
    copy_barcode => ITEM_BARCODE
});
is $checkin_resp->{textcode},
    'ITEM_NOT_CATALOGED',
    'It lets the client know that it is a precat, so the client can tell the user to route to cataloging';

$checkout_resp = $script->do_checkout({
    patron => BR4_PATRON_ID,
    barcode => ITEM_BARCODE,
    dummy_title => 'my title',
    precat => 1
});
is $checkout_resp->{textcode},
    'SUCCESS',
    'You can check out a precat with the same barcode again';

$checkin_resp = $script->do_checkin({
    copy_barcode => ITEM_BARCODE
});
is $checkin_resp->{textcode},
    'ITEM_NOT_CATALOGED',
    'The second time you check it in, it still lets you know that it is a precat';

