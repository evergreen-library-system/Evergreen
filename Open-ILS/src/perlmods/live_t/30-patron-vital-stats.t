use strict;
use warnings;

use Test::More tests => 4;

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::Fieldmapper;
our $U = "OpenILS::Application::AppUtils";

my $script = OpenILS::Utils::TestUtils->new;
$script->bootstrap;

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'
});

my $authtoken = $script->authtoken;
ok $authtoken, 'was able to authenticate';

my $new_user = Fieldmapper::actor::user->new;
my $new_card = Fieldmapper::actor::card->new;

$new_card->barcode("30-patron-vital-stats.t");
$new_card->id(-1); # virtual ID
$new_card->usr(undef);
$new_card->isnew(1);

$new_user->cards([ $new_card ]);
$new_user->card($new_card);
$new_user->usrname("30-patron-vital-stats.t");
$new_user->passwd('my-secret-password');
$new_user->family_name('Biscuit');
$new_user->first_given_name('Dog');
$new_user->second_given_name('Delicious');
$new_user->profile(2);
$new_user->home_ou(4); # BR1
$new_user->ident_type(1);
$new_user->isnew(1);

my $new_user_resp = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.patron.update',
    $authtoken,
    $new_user
);

isa_ok $new_user_resp, 'Fieldmapper::actor::user', 'created a patron for our test';

subtest 'It has user info' => sub {
    plan tests => 3;

    my $vital_stats_response = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.opac.vital_stats',
        $authtoken,
        $new_user_resp->id
    );

    is $vital_stats_response->{user}->{first_given_name}, 'Dog', 'It has user first given name';
    is $vital_stats_response->{user}->{second_given_name}, 'Delicious', 'It has user second given name';
    is $vital_stats_response->{user}->{family_name}, 'Biscuit', 'It has user family name';
};

subtest 'It has fine info' => sub {
    plan tests => 3;

    my $grocery = Fieldmapper::money::grocery->new;
    $grocery->billing_location(4);
    $grocery->usr($new_user_resp->id);

    my $xact_id = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.money.grocery.create',
        $script->authtoken,
        $grocery
    );
    my $billing = Fieldmapper::money::billing->new;
    $billing->xact($xact_id);
    $billing->amount(100);
    $billing->btype(101);
    $billing->billing_type('Misc');

    my $billing_id = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.money.billing.create',
        $script->authtoken,
        $billing
    );

    my $vital_stats_response = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.opac.vital_stats',
        $authtoken,
        $new_user_resp->id
    );

    is $vital_stats_response->{fines}->{total_owed}, '100.00', 'It includes grocery/misc bills in total owed';
    is $vital_stats_response->{fines}->{balance_owed}, '100.00', 'It includes grocery/misc bills in balance owed';
    is $vital_stats_response->{fines}->{total_paid}, '0.0', 'It notices there have not yet been any payments';
};

# clean up
$U->simplereq(
    'open-ils.actor',
    # use the .override version, since there are open transactions
    # on this account
    'open-ils.actor.user.delete.override',
    $authtoken,
    $new_user_resp->id
);
