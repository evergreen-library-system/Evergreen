use strict;
use warnings;

use Test::More tests => 3;

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::Fieldmapper;
our $U = "OpenILS::Application::AppUtils";

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap();

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'
});

my $authtoken = $script->authtoken;
ok($authtoken, 'was able to authenticate');

my $new_user = Fieldmapper::actor::user->new();
my $new_card = Fieldmapper::actor::card->new();

$new_card->barcode("felinity_$$");
$new_card->id(-1); # virtual ID
$new_card->usr(undef);
$new_card->isnew(1);

$new_user->cards([ $new_card ]);
$new_user->card($new_card);
$new_user->usrname("felinity_$$");
$new_user->passwd('catsrule');
$new_user->family_name('Doe');
$new_user->first_given_name('Jane');
$new_user->profile(2);
$new_user->home_ou(4);
$new_user->ident_type(1);
$new_user->isnew(1);

my $resp = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.patron.update',
    $authtoken,
    $new_user
);

isa_ok($resp, 'Fieldmapper::actor::user', 'new patron');

$script->authenticate({
    username => "felinity_$$",
    password => 'catsrule',
    type => 'opac',
});
my $opac_authtoken = $script->authtoken;
ok($opac_authtoken, 'was able to authenticate using new patron');

# clean up
$U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.delete',
    $authtoken,
    $resp->id()
);
