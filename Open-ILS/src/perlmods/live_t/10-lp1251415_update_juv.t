#!perl

use Test::More tests => 8;

diag("Test juv-to-adult batch updater.");

use strict; use warnings;

use constant USER_ID => 2;

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $e = new_editor(xact => 1);
$e->init;

# -------------
# User is 19 years old.  Juv-to-adult with 18 years should clear the flag.

my $user = $e->retrieve_actor_user(USER_ID);

my $dt = DateTime->now;
$dt->set_year($dt->year - 19);
$user->dob($dt->strftime('%F'));
$user->juvenile('t');
my $stat = $e->update_actor_user($user);
ok($stat, 'User update succeeded');
$e->xact_commit;

my $storage = $script->session('open-ils.storage');
my $req = $storage->request(
    'open-ils.storage.actor.user.juvenile_to_adult', '18 years');
$req->recv;

$e->xact_begin;
$user = $e->retrieve_actor_user(USER_ID);
is($user->juvenile, 'f', 'Juvenile flag should be false');

# -------------
# User is 17 years old.  Juv-to-adult with 18 years should leave the flag.

$dt = DateTime->now;
$dt->set_year($dt->year - 17);
$user->dob($dt->strftime('%F'));
$user->juvenile('t');
$stat = $e->update_actor_user($user);
ok($stat, 'User update succeeded');
$e->xact_commit;

$req = $storage->request(
    'open-ils.storage.actor.user.juvenile_to_adult', '18 years');
$req->recv;

$e->xact_begin;
$user = $e->retrieve_actor_user(USER_ID);
is($user->juvenile, 't', 'Juvenile flag should be true');

# -------------
# User is 17 years old, but the juv org unit setting is 16,
# so the flag should be cleared.

my $aous = Fieldmapper::actor::org_unit_setting->new;
$aous->org_unit(1);
$aous->name('global.juvenile_age_threshold');
$aous->value('"16 years"');
$stat = $e->create_actor_org_unit_setting($aous);
ok($stat, 'Org unit setting create successfully');
$e->xact_commit;

# passing "18 years", but the org unit setting should supercede it.
$req = $storage->request(
    'open-ils.storage.actor.user.juvenile_to_adult', '18 years');
$req->recv;

$user = $e->retrieve_actor_user(USER_ID);
is($user->juvenile, 'f', 'Juvenile flag should be false');

# -------------
# Delete the user.  No modification should occur.
$user->juvenile('t');
$user->deleted('t');
$e->xact_begin;
$stat = $e->update_actor_user($user);
ok($stat, 'User successfully deleted');
$e->xact_commit;

# passing "18 years", but the org unit setting should supercede it.
$req = $storage->request(
    'open-ils.storage.actor.user.juvenile_to_adult', '18 years');
$req->recv;

$user = $e->retrieve_actor_user(USER_ID);
is($user->juvenile, 't', 'Juvenile flag should be left true after deletion');

# for ease of repeating this test, delete the new org setting
$e->xact_begin;
$aous = $e->search_actor_org_unit_setting(
    {name => 'global.juvenile_age_threshold', org_unit => 1})->[0];
$e->delete_actor_org_unit_setting($aous);
$e->commit;

