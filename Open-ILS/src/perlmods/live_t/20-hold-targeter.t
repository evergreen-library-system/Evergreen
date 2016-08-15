#!perl
use strict;
use warnings;

use Test::More tests => 15;
diag("General hold targeter tests");

use OpenILS::Const qw/:const/;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::HoldTargeter;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

my $script = OpenILS::Utils::TestUtils->new();
my $targeter = OpenILS::Utils::HoldTargeter->new;
my $e = new_editor();

$script->bootstrap;
$e->init;

# == Targeting Concerto hold 1.  Title hold.

my $hold_id = 1;
my $result = $targeter->target(hold => $hold_id)->[0];

ok($result->{success}, "Targeting hold $hold_id returned success");

# Concerto hold 1 targets record 2 with a pickup_lib of 5.  
# There are several viable copies with circ lib 5.
my $current_copy = $e->retrieve_asset_copy($result->{target});
is($current_copy->circ_lib.'', '5', 'Targeted copy lives at pickup lib');

my $maps = $e->search_action_hold_copy_map([
    {hold => $hold_id},
    {
        flesh => 2, 
        flesh_fields => {ahcm => ['target_copy'], acp => ['call_number']}
    }
]);

is(scalar(@$maps), 25, "Hold $hold_id has 25 mapped potential copies");

is(scalar(grep {$_->target_copy->call_number->record != 2} @$maps), 0,
    'All targeted copies belong to the targeted bib record');

# Retarget to confirm a new copy is selected and that the previously
# targeted item has a new entry in action.unfulfilled_hold_list.

$result = $targeter->target(hold => $hold_id)->[0];

isnt($result->{target}, $current_copy->id, 
    'Second targeter run on hold 1 selected targeted a different copy');

my $unfulfilled = $e->search_action_unfulfilled_hold_list(
    {hold => $hold_id, current_copy => $current_copy->id})->[0];

isnt($unfulfilled, undef, 'Previous copy has unfulfilled hold entry');

my $prev_target = $result->{target};

$result = $targeter->target(hold => $hold_id, skip_viable => 1)->[0];

is($result->{target}, $prev_target, 
    "Hold $hold_id target remains the same with --skip-viable");

$maps = $e->search_action_hold_copy_map({hold => $hold_id});

is(scalar(@$maps), 25, 
    "Hold $hold_id retains 25 mapped potential copies with --skip-viable");


# == Metarecord hold tests
#
# Concerto hold 263 is a metarecord hold with pickup_lib 4, target 42, and 
# holdable_format '{"0":[{"_attr":"mr_hold_format","_val":"score"}]}'.

$hold_id = 263;
$result = $targeter->target(hold => $hold_id)->[0];

ok($result->{success}, "Targeting hold $hold_id returned success");

$current_copy = $e->retrieve_asset_copy($result->{target});
is($current_copy->circ_lib.'', '9', 'Targeted copy lives at pickup lib');

$maps = $e->search_action_hold_copy_map([
    {hold => $hold_id},
    {
        flesh => 2, 
        flesh_fields => {ahcm => ['target_copy'], acp => ['call_number']}
    }
]);

is(scalar(@$maps), 22, "Hold $hold_id has 22 mapped potential copies");

# Only 1 bib record (45) links to metarecord 42.  It also satisfies the 
# holdable_format criteria.
is(scalar(grep {$_->target_copy->call_number->record != 45} @$maps), 0,
    'All targeted copies belong to the targeted bib record');

# Bib 101 has mr_hold_format 'book'.  Link it to the targeted metabib
# and confirm the targeter does not select it.

$e->xact_begin;
my $mrmap_101 = $e->search_metabib_metarecord_source_map({source => 101})->[0];
my $orig_101_mr = $mrmap_101->metarecord;
$mrmap_101->metarecord(42);
$e->update_metabib_metarecord_source_map($mrmap_101) or die $e->die_event;

# Temporarily point the original bib (42) at another metarecord

my $mrmap_42 = $e->search_metabib_metarecord_source_map({source => 45})->[0];
my $orig_42_mr = $mrmap_42->metarecord;
$mrmap_42->metarecord(1);
$e->update_metabib_metarecord_source_map($mrmap_42) or die $e->die_event;
$e->xact_commit;

# This time no copies should be targeted, since no records match
# the holdable_formats criteria.
$result = $targeter->target(hold => $hold_id)->[0];

isnt($result->{success}, 1, 
    'Unable to target MR hold without copies matching holdable_format');

$maps = $e->search_action_hold_copy_map({hold => $hold_id});

is(scalar(@$maps), 0, 
    'No potential copies exist that match the holdable_format criteria');

# Now remove the holdable format restriction and copies belonging to
# record 101 should now be acceptable potential copies.
$e->xact_begin;
my $hold = $e->retrieve_action_hold_request($hold_id);
$hold->clear_holdable_formats;
$e->update_action_hold_request($hold) or die $e->die_event;
$e->xact_commit;

$result = $targeter->target(hold => $hold_id)->[0];

$current_copy = $e->retrieve_asset_copy([
    $result->{target},
    {flesh => 1, flesh_fields => {acp => ['call_number']}}
]);

is($current_copy->call_number->record.'', '101', 
    'Metarecord hold targeted after removing holdable_format restriction');

# Return the hold and bib records to their original metarecord state 
# for re-test-ability.
$e->xact_begin;
$hold->holdable_formats('{"0":[{"_attr":"mr_hold_format","_val":"score"}]}');
$e->update_action_hold_request($hold) or die $e->die_event;
$mrmap_101->metarecord($orig_101_mr);
$mrmap_42->metarecord(42);
$e->update_metabib_metarecord_source_map($mrmap_101) or die $e->die_event;
$e->update_metabib_metarecord_source_map($mrmap_42) or die $e->die_event;
$e->xact_commit;


