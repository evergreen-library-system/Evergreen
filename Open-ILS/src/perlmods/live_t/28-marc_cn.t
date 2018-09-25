#!perl

use Test::More tests => 1;

diag("Test retrieving call numbers from bibliographic records.");

use strict; use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

our $apputils   = "OpenILS::Application::AppUtils";

my $resp = $apputils->simplereq(
    'open-ils.cat',
    'open-ils.cat.biblio.record.marc_cn.retrieve',
    46,
    1
);

is_deeply($resp, [{ '050' => 'ML60 .C22' }], 'LP#1576727: extracted LC call number includes space');
