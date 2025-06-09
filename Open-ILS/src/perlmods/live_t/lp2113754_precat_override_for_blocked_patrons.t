#!perl
use strict; use warnings;
use Test::More tests => 5;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw/:const/;

diag('LP2113754: Override precat checkouts for blocked patrons');

use constant {
    AUTH_USERNAME => 'admin',
    AUTH_PASSWORD => 'demo123',
    AUTH_TYPE     => 'staff',
    WS_NAME       => 'BR1-test-lp2113754.t',
    WS_OU         => 4,
    PATRON_ID     => 71,
    COPY_BARCODE  => 'you got a fast car'
};

my $U = 'OpenILS::Application::AppUtils';
my $script = OpenILS::Utils::TestUtils->new;
$script->bootstrap;


subtest('Login in', sub {
    plan tests => 4;

    # Log in
    my $credentials = {
        username => AUTH_USERNAME,
        password => AUTH_PASSWORD,
        type     => AUTH_TYPE
    };
    $script->authenticate($credentials);
    ok($script->authtoken, 'Logged in');


    # Find or register workstation
    my $ws = $script->find_or_register_workstation(WS_NAME, WS_OU);
    ok(!ref($ws), 'Found or registered workstation');


    # Logout so we can use the workstation.
    $script->logout();
    ok(!$script->authtoken, 'Logged out');


    # Log in with workstation
    $credentials->{workstation} = WS_NAME;
    $credentials->{password} = AUTH_PASSWORD;
    $script->authenticate($credentials);
    ok($script->authtoken, 'Logged in with workstation');
});


# Add PATRON_EXCEEDS_FINES penalty to patron
my $ausp = Fieldmapper::actor::user_standing_penalty->new();
$ausp->org_unit(WS_OU);
$ausp->set_date('now');
$ausp->staff(1);
$ausp->standing_penalty(OILS_PENALTY_PATRON_EXCEEDS_FINES);
$ausp->usr(PATRON_ID);

my $response = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.note.apply',
    $script->authtoken, $ausp
);
ok(
    !ref($response),
    'Added PATRON_EXCEEDS_FINES penalty to patron'
);
$ausp->id($response);


# Attempt a checkout with an uncataloged barcode
my $checkout_args = {
    copy_barcode => COPY_BARCODE,
    patron_id    => PATRON_ID
};

$response = $script->do_checkout($checkout_args);
is(
    $response->{textcode}, 'ITEM_NOT_CATALOGED',
    'Checkout attempt returned ITEM_NOT_CATALOGED'
);


# Attempt a precat checkout (simulate precat dialog submission)
$checkout_args->{dummy_title} = 'Title';
$checkout_args->{precat} = 1;

$response = $script->do_checkout($checkout_args);
is(
    $response->{textcode}, 'PATRON_EXCEEDS_FINES',
    'Precat checkout attempt returned PATRON_EXCEEDS_FINES'
);


# Attempt a precat checkout override
$response = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.checkout.full.override',
    $script->authtoken, $checkout_args
);
ok(
    !$U->event_code($response),
    'Precat checkout override was successful'
);


# Clean up
$script->do_checkin({ copy_barcode => COPY_BARCODE });

$U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.note.remove',
    $script->authtoken, $ausp
);

$script->logout();
