#!perl
 
use Test::More tests => 1;

diag("Test the course materials module.");

use strict; use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

our $apputils   = "OpenILS::Application::AppUtils";

is(1, 1, 'placeholder');


# Test: can attach a bib record with located URI
# Test: cannot attach a bib record without a located URI

# Test: can detach an item (just delete this)
# Test: can detach a record that is not temporary (just delete this)
# Test: can detach a record that is temporary (delete this, and delete the record too)
