#!perl
use strict; use warnings;

use Test::More tests => 1;

diag("Tests CSTORE");

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor (':funcs');

my $script = OpenILS::Utils::TestUtils->new;
$script->bootstrap;

my $e = new_editor;
$e->init;

subtest('using functions in a where clause', sub {
    plan tests => 2;

    my $res = $e->json_query({
        from => 'acp',
        where => {barcode => ['xml_escape', 'CONC90000436']}
    });
    is scalar(@{$res}), 1, 'it can use a function to modify a param';

    $res = $e->json_query({
        from => 'acp',
        where => {id => {'=' => ['(SELECT 1 FROM actor.change_password(1,\'squid\'))--']}}
    });
    ok $e->event, 'it rejects sql injection';
});

