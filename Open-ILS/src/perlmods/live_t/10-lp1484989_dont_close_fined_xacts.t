#!perl

use Test::More tests => 2;

diag("Make sure we don't close xacts with fines");

use strict;
use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();
#our $apputils   = "OpenILS::Application::AppUtils";
my $storage_ses = $script->session('open-ils.storage');
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});
ok( $script->authtoken, 'Have an authtoken');

my $barcode = 'CONC4000054';
my $circ_id = 18;

my $checkin_resp = $script->do_checkin_override({
    barcode => $barcode});

my $circ_req = $storage_ses->request('open-ils.storage.direct.action.circulation.retrieve', $circ_id);
if (my $circ_resp = $circ_req->recv) {
    if (my $circ = $circ_resp->content) {
        ok(
            !$circ->xact_finish,
            'Circ with id = ' . $circ_id . ' is overdue with fines, so xact_finish isn\'t set'
        );
    } else {
        fail('unable to retrieve circ');
    }
}

$script->logout();
