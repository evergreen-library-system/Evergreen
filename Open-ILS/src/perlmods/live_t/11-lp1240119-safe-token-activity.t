#!perl
use strict; use warnings;
use Test::More tests => 4;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

diag("Tests safe auth token user activity tracking");

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $e = new_editor();
$e->init;

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'
});

ok($script->authtoken, 'Have an authtoken');

my $actor_ses = $script->session('open-ils.actor');
my $req = $actor_ses->request(
    'open-ils.actor.session.safe_token', $script->authtoken);

my $safe_token = $req->recv->content;

ok($safe_token, 'Have safe token');

my $act_count = scalar(@{$e->search_actor_usr_activity({usr => 1})});

$req = $actor_ses->request(
    'open-ils.actor.safe_token.home_lib.shortname', $safe_token);

my $home_ou = $req->recv->content;

ok($home_ou, 'Retrieved home org unit');

my $act_count2 = scalar(@{$e->search_actor_usr_activity({usr => 1})});

is($act_count2, $act_count + 1, 'User activity entry created');

