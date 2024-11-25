#!perl
use strict; use warnings;
use Test::More tests => 8;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $e = new_editor(xact => 1);
$e->init;

diag('LP#2089419: test parsing of limit and offset parameters of C database search code');

my $ous = $e->search_actor_org_unit([
    { parent_ou => { "!=" => undef } },
    { order_by => { "aou" => "id DESC" }, limit => 3 }
]);

is(scalar(@$ous), 3, 'LP#2089419: got three results when limit expressed as an integer');

$ous = $e->search_actor_org_unit([
    { parent_ou => { "!=" => undef } },
    { order_by => { "aou" => "id DESC" }, limit => "3" }
]);
is(scalar(@$ous), 3, 'LP#2089419: got three results when limit expressed as a string');

$ous = $e->search_actor_org_unit([
    { parent_ou => { "!=" => undef } },
    { order_by => { "aou" => "id DESC" }, limit => "abc" }
]);
is(scalar(@$ous), 0, 'LP#2089419: non-numeric limit treated as limit 0');

$ous = $e->search_actor_org_unit([
    { parent_ou => { "!=" => undef } },
    { order_by => { "aou" => "id DESC" } }
]);
cmp_ok(scalar(@$ous), '>=', 8, 'LP#2089419: got expected number of results when no limit specified');

# grab list of OUs for some tests of setting the offset
my @ids = map { $_->id } @$ous;

$ous = $e->search_actor_org_unit([
    { parent_ou => { "!=" => undef } },
    { order_by => { "aou" => "id DESC"}, offset => 1 }
]);
is($ous->[0]->id, $ids[1], 'LP#2089419: offset expressed as integer returning expected first result');

$ous = $e->search_actor_org_unit([
    { parent_ou => { "!=" => undef } },
    { order_by => { "aou" => "id DESC"}, offset => "1" }
]);
is($ous->[0]->id, $ids[1], 'LP#2089419: offset expressed as string returning expected first result');

$ous = $e->search_actor_org_unit([
    { parent_ou => { "!=" => undef } },
    { order_by => { "aou" => "id DESC"}, offset => "abc" }
]);
is($ous->[0]->id, $ids[0], 'LP#2089419: non-numeric offset treated as offset 0 (first element)');
is(scalar(@$ous), scalar(@ids), 'LP#2089419: non-numeric offset treated as offset 0 (number of results)');
