#!perl
use strict; use warnings;

use Test::More tests => 4;

diag("Tests searching for patrons by profile");

use DateTime;
use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';
$script->bootstrap;

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'
});

ok($script->authtoken, 'Have an authtoken');

my $results = $apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.patron.search.advanced.fleshed.atomic',
    $script->authtoken,
    {"family_name" => {"value" => "smith", "group" =>  0}},
    10,
    [],
    undef,
    1,
    ["cards"]
);

cmp_ok(@$results, '>=', 1, 'Patron search on "Smith" returns at least one result');

$results = $apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.patron.search.advanced.fleshed.atomic',
    $script->authtoken,
    {"profile" => {"value" => 3, "group" =>  0}},
    10,
    [],
    undef,
    1,
    ["cards"]
);

cmp_ok(@$results, '==', 0, 'Patron search profile 3 (staff) in group 0 returns at zero results');

$results = $apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.patron.search.advanced.fleshed.atomic',
    $script->authtoken,
    {"profile" => {"value" => 3, "group" =>  5}},
    10,
    [],
    undef,
    1,
    ["cards"]
);

cmp_ok(@$results, '>=', 1, 'Patron search profile 3 (staff) in group 5 returns at least one result');
