#!perl
use strict;
use warnings;

use Test::More tests => 82;
diag("General hold targeter tests");

use OpenILS::Const qw/:const/;
use OpenILS::Utils::TestUtils;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

my $script = OpenILS::Utils::TestUtils->new();
my $U = 'OpenILS::Application::AppUtils';
my $e = new_editor();

$script->bootstrap;
$e->init;

sub target {
    return $U->simplereq(
        'open-ils.hold-targeter', 
        'open-ils.hold-targeter.target', 
        @_
    );
}

# == Targeting Concerto hold 67.  Title hold.

my $hold_id = 67;
my $result = target({hold => $hold_id});

ok($result->{success}, "Targeting hold $hold_id returned success");

# Concerto hold 67 targets record 70 with a pickup_lib of 4.  
# There are several viable copies with circ lib 4.
my $current_copy = $e->retrieve_asset_copy($result->{target});
is($current_copy->circ_lib.'', '4', 'Targeted copy lives at pickup lib');

my $maps = $e->search_action_hold_copy_map([
    {hold => $hold_id},
    {
        flesh => 2, 
        flesh_fields => {ahcm => ['target_copy'], acp => ['call_number']}
    }
]);

is(scalar(@$maps), 29, "Hold $hold_id has 29 mapped potential copies");

is(scalar(grep {$_->target_copy->call_number->record != 70} @$maps), 0,
    'All targeted copies belong to the targeted bib record');

# Retarget to confirm a new copy is selected and that the previously
# targeted item has a new entry in action.unfulfilled_hold_list.

$result = target({hold => $hold_id});

isnt($result->{target}, $current_copy->id, 
    'Second targeter run on hold 67 selected targeted a different copy');

my $unfulfilled = $e->search_action_unfulfilled_hold_list(
    {hold => $hold_id, current_copy => $current_copy->id})->[0];

isnt($unfulfilled, undef, 'Previous copy has unfulfilled hold entry');

my $prev_target = $result->{target};

$result = target({hold => $hold_id, soft_retarget_interval => '0s'});

is($result->{target}, $prev_target, 
    "Hold $hold_id target remains the same with soft_retarget_interval");

$maps = $e->search_action_hold_copy_map({hold => $hold_id});

is(scalar(@$maps), 29, 
    "Hold $hold_id retains 29 mapped potential copies with soft_retarget_interval");


# == Metarecord hold tests
#
# Concerto hold 263 is a metarecord hold with pickup_lib 4, target 42, and 
# holdable_format '{"0":[{"_attr":"mr_hold_format","_val":"score"}]}'.

$hold_id = 263;
$result = target({hold => $hold_id});

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

is(scalar(@$maps), 24, "Hold $hold_id has 24 mapped potential copies");

# Only 1 bib record (42) links to metarecord 42.  It also satisfies the 
# holdable_format criteria.
is(scalar(grep {$_->target_copy->call_number->record != 42} @$maps), 0,
    'All targeted copies belong to the targeted bib record');

# Bib 101 has mr_hold_format 'book'.  Link it to the targeted metabib
# and confirm the targeter does not select it.

$e->xact_begin;
my $mrmap_101 = $e->search_metabib_metarecord_source_map({source => 101})->[0];
my $orig_101_mr = $mrmap_101->metarecord;
$mrmap_101->metarecord(42);
$e->update_metabib_metarecord_source_map($mrmap_101) or die $e->die_event;

# Temporarily point the original bib (42) at another metarecord

my $mrmap_42 = $e->search_metabib_metarecord_source_map({source => 42})->[0];
my $orig_42_mr = $mrmap_42->metarecord;
$mrmap_42->metarecord(1);
$e->update_metabib_metarecord_source_map($mrmap_42) or die $e->die_event;
$e->xact_commit;

# This time no copies should be targeted, since no records match
# the holdable_formats criteria.
$result = target({hold => $hold_id});

isnt($result->{success}, 1, 
    'Unable to target MR hold without copies matching holdable_format');

$maps = $e->search_action_hold_copy_map({hold => $hold_id});

is(scalar(@$maps), 0, 
    'No potential copies exist that match the holdable_format criteria');

# Should be a "Hopeless" (TM) hold now
my $hopeless_hold = $e->retrieve_action_hold_request($hold_id);
ok($hopeless_hold->hopeless_date, "Hold $hold_id now has a Hopeless Date");

# Now remove the holdable format restriction and copies belonging to
# record 101 should now be acceptable potential copies.
$e->xact_begin;
my $hold = $e->retrieve_action_hold_request($hold_id);
$hold->clear_holdable_formats;
$e->update_action_hold_request($hold) or die $e->die_event;
$e->xact_commit;

$result = target({hold => $hold_id});

$current_copy = $e->retrieve_asset_copy([
    $result->{target},
    {flesh => 1, flesh_fields => {acp => ['call_number']}}
]);

is($current_copy->call_number->record.'', '101', 
    'Metarecord hold targeted after removing holdable_format restriction');

# Should no longer be a Hopeless Hold
$hopeless_hold = $e->retrieve_action_hold_request($hold_id);
ok(!$hopeless_hold->hopeless_date, "Hold $hold_id no longer has a Hopeless Date");

# Unless all Available is now Hopeless Prone :D
my $available_status = $e->retrieve_config_copy_status(0);
$available_status->hopeless_prone(1);
$e->xact_begin;
$e->update_config_copy_status($available_status);
$e->xact_commit;
$result = target({hold => $hold_id});
$hopeless_hold = $e->retrieve_action_hold_request($hold_id);
ok($hopeless_hold->hopeless_date, "Hold $hold_id has a Hopeless Date again");

$available_status->hopeless_prone(0);
$e->xact_begin;
$e->update_config_copy_status($available_status);
$e->xact_commit;

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

# Test Lp 1904737 hold status expansion.
$hold_id = 67;
$hold = $e->retrieve_action_hold_request($hold_id);
my $copy = $e->retrieve_asset_copy($hold->current_copy());
my $saved_status = $copy->status();
# change its status to one that won't fill holds
my $cataloging_status = $e->retrieve_config_copy_status(11);
$copy->status($cataloging_status->id());
$e->xact_begin;
$e->update_asset_copy($copy);
$e->xact_commit();
$result = target({hold => $hold->id()});
ok($result->{success}, "Targeting hold $hold_id returned success");
$hold = $e->retrieve_action_hold_request($hold_id);
isnt($copy->id(), $hold->current_copy(), "Hold $hold_id has new current copy");
# Check the hold copy map, it should be 1 less than before.
$maps = $e->search_action_hold_copy_map({hold => $hold_id});
is(scalar(@$maps), 28, "Hold $hold_id has 28 mapped potential copies");
# Check asset.staff_ou_metarecord_copy_count
$result = $e->json_query({from => ["asset.staff_ou_metarecord_copy_count", 4, 70]});
is(scalar(@$result), 3, "asset.staff_ou_metarecord_copy_count returns 3 rows");
for (my $i = 0; $i < 3; $i++) {
    my $row = $result->[$i];
    if ($i == 0) {
        is($row->{depth}, 0, "Depth of first row is 0");
        is($row->{org_unit}, 1, "Org Unit of first row is 1");
        is($row->{visible}, 31, "Visible of first row is 31");
        is($row->{available}, 25, "Available of first row is 25");
    } elsif ($i == 1) {
        is($row->{depth}, 1, "Depth of second row is 1");
        is($row->{org_unit}, 2, "Org Unit of second row is 2");
        is($row->{visible}, 14, "Visible of second row is 14");
        is($row->{available}, 11, "Available of second row is 11");
    } elsif ($i == 2) {
        is($row->{depth}, 2, "Depth of third row is 2");
        is($row->{org_unit}, 4, "Org Unit of third row is 4");
        is($row->{visible}, 7, "Visible of third row is 7");
        is($row->{available}, 5, "Available of third row is 5");
    }
}
# Make copy status holdable, retarget the hold and check values again.
$cataloging_status->holdable('t');
$e->xact_begin;
$e->update_config_copy_status($cataloging_status);
$e->xact_commit;
$cataloging_status = $e->retrieve_config_copy_status(11);
is($cataloging_status->holdable(), 't', "Cataloging status is holdable");
$result = target({hold => $hold->id()});
ok($result->{success}, "Targeting hold $hold_id returned success");
$maps = $e->search_action_hold_copy_map({hold => $hold_id});
is(scalar(@$maps), 29, "Hold $hold_id has 29 mapped potential copies");
# Check asset.staff_ou_metarecord_copy_count
$result = $e->json_query({from => ["asset.staff_ou_metarecord_copy_count", 4, 70]});
is(scalar(@$result), 3, "asset.staff_ou_metarecord_copy_count returns 3 rows");
for (my $i = 0; $i < 3; $i++) {
    my $row = $result->[$i];
    if ($i == 0) {
        is($row->{depth}, 0, "Depth of first row is 0");
        is($row->{org_unit}, 1, "Org Unit of first row is 1");
        is($row->{visible}, 31, "Visible of first row is 31");
        is($row->{available}, 25, "Available of first row is 25");
    } elsif ($i == 1) {
        is($row->{depth}, 1, "Depth of second row is 1");
        is($row->{org_unit}, 2, "Org Unit of second row is 2");
        is($row->{visible}, 14, "Visible of second row is 14");
        is($row->{available}, 11, "Available of second row is 11");
    } elsif ($i == 2) {
        is($row->{depth}, 2, "Depth of third row is 2");
        is($row->{org_unit}, 4, "Org Unit of third row is 4");
        is($row->{visible}, 7, "Visible of third row is 7");
        is($row->{available}, 5, "Available of third row is 5");
    }
}
# Make copy status available, retarget the hold and check values again.
$cataloging_status->is_available('t');
$e->xact_begin;
$e->update_config_copy_status($cataloging_status);
$e->xact_commit;
$cataloging_status = $e->retrieve_config_copy_status(11);
is($cataloging_status->is_available(), 't', "Cataloging status is available");
$result = target({hold => $hold->id()});
ok($result->{success}, "Targeting hold $hold_id returned success");
$maps = $e->search_action_hold_copy_map({hold => $hold_id});
is(scalar(@$maps), 29, "Hold $hold_id has 29 mapped potential copies");
# Check asset.staff_ou_metarecord_copy_count
$result = $e->json_query({from => ["asset.staff_ou_metarecord_copy_count", 4, 70]});
is(scalar(@$result), 3, "asset.staff_ou_metarecord_copy_count returns 3 rows");
for (my $i = 0; $i < 3; $i++) {
    my $row = $result->[$i];
    if ($i == 0) {
        is($row->{depth}, 0, "Depth of first row is 0");
        is($row->{org_unit}, 1, "Org Unit of first row is 1");
        is($row->{visible}, 31, "Visible of first row is 31");
        is($row->{available}, 26, "Available of first row is 26");
    } elsif ($i == 1) {
        is($row->{depth}, 1, "Depth of second row is 1");
        is($row->{org_unit}, 2, "Org Unit of second row is 2");
        is($row->{visible}, 14, "Visible of second row is 14");
        is($row->{available}, 12, "Available of second row is 12");
    } elsif ($i == 2) {
        is($row->{depth}, 2, "Depth of third row is 2");
        is($row->{org_unit}, 4, "Org Unit of third row is 4");
        is($row->{visible}, 7, "Visible of third row is 7");
        is($row->{available}, 6, "Available of third row is 6");
    }
}
# Reset the copy status, retarget the hold, and check the numbers one last time.
$copy->status($saved_status);
$e->xact_begin;
$e->update_asset_copy($copy);
$e->xact_commit;
$copy = $e->retrieve_asset_copy($copy->id());
is($copy->status(), $saved_status, "Copy status is $saved_status");
$result = target({hold => $hold->id()});
ok($result->{success}, "Targeting hold $hold_id returned success");
$maps = $e->search_action_hold_copy_map({hold => $hold_id});
is(scalar(@$maps), 29, "Hold $hold_id has 29 mapped potential copies");
# Check asset.staff_ou_metarecord_copy_count
$result = $e->json_query({from => ["asset.staff_ou_metarecord_copy_count", 4, 70]});
is(scalar(@$result), 3, "asset.staff_ou_metarecord_copy_count returns 3 rows");
for (my $i = 0; $i < 3; $i++) {
    my $row = $result->[$i];
    if ($i == 0) {
        is($row->{depth}, 0, "Depth of first row is 0");
        is($row->{org_unit}, 1, "Org Unit of first row is 1");
        is($row->{visible}, 31, "Visible of first row is 31");
        is($row->{available}, 26, "Available of first row is 26");
    } elsif ($i == 1) {
        is($row->{depth}, 1, "Depth of second row is 1");
        is($row->{org_unit}, 2, "Org Unit of second row is 2");
        is($row->{visible}, 14, "Visible of second row is 14");
        is($row->{available}, 12, "Available of second row is 12");
    } elsif ($i == 2) {
        is($row->{depth}, 2, "Depth of third row is 2");
        is($row->{org_unit}, 4, "Org Unit of third row is 4");
        is($row->{visible}, 7, "Visible of third row is 7");
        is($row->{available}, 6, "Available of third row is 6");
    }
}

# Reset cataloging status
$cataloging_status->holdable('f');
$cataloging_status->is_available('f');
$e->xact_begin();
$e->update_config_copy_status($cataloging_status);
$e->commit();
