#!perl

use Test::More tests => 4;

diag("Tests barcode completion");

use strict; use warnings;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor (':funcs');
use OpenILS::Utils::Fieldmapper;
our $U = "OpenILS::Application::AppUtils";

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap();

# test values
my $org = 5; # test org: BR2
my $bc_base = 'bc_complete_user';
my $bc_prefix = 'JUSTATEST_';
my $bc = $bc_prefix . $bc_base;

# get authtoken for future use
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'
});

my $authtoken = $script->authtoken;
ok($authtoken, 'was able to authenticate');

# create test user
my $new_user = Fieldmapper::actor::user->new();
my $new_card = Fieldmapper::actor::card->new();

$new_card->barcode($bc);
$new_card->id(-1); # virtual ID
$new_card->usr(undef);
$new_card->isnew(1);

$new_user->cards([ $new_card ]);
$new_user->card($new_card);
$new_user->usrname($bc);
$new_user->passwd('dummypwd');
$new_user->family_name('Doe');
$new_user->first_given_name('Jane');
$new_user->profile(2);
$new_user->home_ou($org);
$new_user->ident_type(1);
$new_user->isnew(1);

my $user = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.patron.update',
    $authtoken,
    $new_user
);
isa_ok($user, 'Fieldmapper::actor::user', 'new patron');

# create barcode completion rule
my $new_rule = Fieldmapper::config::barcode_completion->new();

$new_rule->isnew(1);
$new_rule->active('t');
$new_rule->org_unit($org);
$new_rule->prefix($bc_prefix);
$new_rule->actor('t');
$new_rule->asset('f'); # TODO test item barcodes too

my $e = new_editor(xact => 1);
$e->init;

$e->xact_begin;
$e->create_config_barcode_completion($new_rule);
$e->xact_commit;

my $bc_rule = $e->search_config_barcode_completion({
    org_unit => 5, actor => 't', prefix => $bc_prefix
})->[0];
isa_ok($bc_rule, 'Fieldmapper::config::barcode_completion', 'Created and retrieved new barcode completion rule');

my $get_barcodes = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.get_barcodes',
    $authtoken, $org, 'actor', $bc_base
);
is($get_barcodes->[0]->{barcode}, $bc, 'Retrieved correct user with barcode completion');

# clean up
$U->simplereq(
    'open-ils.actor',
    'open-ils.actor.user.delete',
    $authtoken,
    $user->id()
);
$e->xact_begin;
$e->delete_config_barcode_completion($bc_rule);
$e->commit;

