#!perl

use Test::More tests => 5;

diag("Tests Anonymous PCRUD personality for CStoreEditor");

use strict; use warnings;

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor (':funcs', personality => 'open-ils.pcrud');
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $e = new_editor;
$e->init;

is ($e->personality, 'open-ils.pcrud', 'Confirm personality');

my $org = $e->retrieve_actor_org_unit(1);
is($org->id, 1, 'Anon org unit retrieved');

my $user = $e->retrieve_actor_user(1);
is($user,  undef, 'Anon user not retrieved');

$org = $e->search_actor_org_unit({id => 1})->[0];
is($org->id, 1, 'Anon org unit searched');

$user = $e->search_actor_user({id => 1})->[0];
is($user,  undef, 'Anon user not searched');


