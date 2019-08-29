#!perl

use Test::More tests => 1;

diag("Test creating authority records from a bibliographic field.");

use strict; use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

our $apputils   = "OpenILS::Application::AppUtils";

my $field = {
    'tag' => '710',
    'ind1' => '2',
    'subfields' => [['a', 'Evergreen Club Contemporary Gamelan']]
    };
my $resp = $apputils->simplereq(
    'open-ils.cat',
    'open-ils.cat.authority.record.create_from_bib.readonly',
    $field,
    'catLibrary'
);

like($resp,
    '/<datafield tag=\"110\" ind1=\"2\" ind2=\" \"><subfield code=\"a\">Evergreen Club Contemporary Gamelan<\/subfield><\/datafield>/',
    'Can create an authority record from a bib field');

