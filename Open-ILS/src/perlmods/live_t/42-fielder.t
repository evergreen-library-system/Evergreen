#!perl

use strict; use warnings;

use Test::More tests => 1;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

diag('Test open-ils.fielder');

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;
our $apputils = "OpenILS::Application::AppUtils";

subtest('fielder rejects function calls as query filters', sub {
    plan tests => 2;

    my $response = $apputils->simplereq(
        'open-ils.fielder',
        'open-ils.fielder.aou.atomic',
        {
            query => { id => { in => [
                1,2
            ]}}
        }
    );
    ok(ref($response) eq 'ARRAY' && scalar(@{ $response }) == 2, 'Fielder allows in => array');
    $response = $apputils->simplereq(
        'open-ils.fielder',
        'open-ils.fielder.aou',
        {
            query => { id => { "=" => [
                'asset.merge_record_assets', 200, 201
            ]}}
        }
    );
    ok(ref($response) eq 'HASH' && exists($response->{textcode}), 'Fielder rejects a function call as a query filter');
});
