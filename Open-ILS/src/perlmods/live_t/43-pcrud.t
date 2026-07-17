#!perl
use strict; use warnings;

use Test::More tests => 2;

diag("Tests PCRUD");

use OpenILS::Utils::TestUtils;

my $script = OpenILS::Utils::TestUtils->new;
$script->bootstrap;

my $pcrud_ses = $script->session('open-ils.pcrud');

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});
ok(
    $script->authtoken,
    'Have an authtoken'
);

subtest('exercise stored functions as PCRUD query filters', sub {
    plan tests => 2;

    my $req = $pcrud_ses->request(
            'open-ils.pcrud.search.pgt.atomic',
            $script->authtoken,
            { parent => { '=' => [ "numeric_add", 0, 1 ] } },
            { flesh => -1, flesh_fields => { pgt => [ "children" ] } }
    );
    my $resp = $req->recv;
    is $resp->statusCode, '200', 'PCRUD query filter using a non-volatile function succeeded';

    $req = $pcrud_ses->request(
            'open-ils.pcrud.search.pgt.atomic',
            $script->authtoken,
            { parent => { '=' => [ "asset.merge_record_assets", 11, 12 ] } },
            { flesh => -1, flesh_fields => { pgt => [ "children" ] } }
    );
    $resp = $req->recv;
    is $resp->statusCode, '500', 'PCRUD query filter using a volatile function rejected';

});
