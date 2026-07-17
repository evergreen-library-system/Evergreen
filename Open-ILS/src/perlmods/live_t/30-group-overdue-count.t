use strict;
use warnings;

use Test::More tests => 5;

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
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

use constant PATRON_WITH_4_OVERDUES => 7; # Brittany Walker
use constant PATRON_WITH_6_OVERDUES => 8; # Ernesto Miller

my $editor = new_editor;
$editor->init;

subtest 'setup' => sub {
    plan tests => 4;
    is $editor->retrieve_action_open_circ_count(PATRON_WITH_4_OVERDUES)->overdue, 4, 'patron has 4 overdues';
    is $editor->retrieve_action_open_circ_count(PATRON_WITH_6_OVERDUES)->overdue, 6, 'patron has 6 overdues';
    ok $U->simplereq('open-ils.actor', 'open-ils.actor.usergroup.new', $authtoken, PATRON_WITH_4_OVERDUES),
        'reset group for patron with 4 overdues';
    ok $U->simplereq('open-ils.actor', 'open-ils.actor.usergroup.new', $authtoken, PATRON_WITH_6_OVERDUES),
        'reset group for patron with 6 overdues';
};

subtest 'group with one user' => sub {
    plan tests => 1;
    my $group_id = $editor->retrieve_actor_user(PATRON_WITH_4_OVERDUES)->usrgroup;
    is $U->simplereq('open-ils.actor', 'open-ils.actor.usergroup.members.overdue_count', $authtoken, $group_id),
        4, 'returns the number of overdues for the user';
};

subtest 'group with two users' => sub {
    plan tests => 1;
    my $group_id = $editor->retrieve_actor_user(PATRON_WITH_4_OVERDUES)->usrgroup;
    my $patron_to_add = $editor->retrieve_actor_user(PATRON_WITH_6_OVERDUES);
    $patron_to_add->usrgroup($group_id);
    $editor->xact_begin;
    $editor->update_actor_user($patron_to_add);
    $editor->xact_commit;

    is $U->simplereq('open-ils.actor', 'open-ils.actor.usergroup.members.overdue_count', $authtoken, $group_id),
        10, 'returns the number of overdues for both users in the group';
};

subtest 'cleanup' => sub {
    plan tests => 2;
    ok $U->simplereq('open-ils.actor', 'open-ils.actor.usergroup.new', $authtoken, PATRON_WITH_4_OVERDUES),
        'reset group for patron with 4 overdues';
    ok $U->simplereq('open-ils.actor', 'open-ils.actor.usergroup.new', $authtoken, PATRON_WITH_6_OVERDUES),
        'reset group for patron with 6 overdues';
};
