#!perl

use Test::More tests => 2;

diag("Tests libdbi transaction error reporting");

use strict; use warnings;

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor (':funcs');
use OpenILS::Utils::Fieldmapper;
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $e = new_editor(xact => 1);
$e->init;

# create a copy status object with ID 1, which will fail.
my $stat = Fieldmapper::config::copy_status->new;
$stat->id(1);

# when functioning well, this should happen and fail quickly
my $start = time;
$e->create_config_copy_status($stat);
my $evt = $e->die_event; # this part takes the longest
my $duration = time - $start;

cmp_ok($duration, '<', '10', 
    'Confirm cstore reports standard update query error in a timely fashion');

if ($evt) {
    is($evt->{textcode}, 'DATABASE_UPDATE_FAILED',
        'CStoreEditor returns standard update query error');
} else {
    fail('CStoreEditor returned no event');
}



