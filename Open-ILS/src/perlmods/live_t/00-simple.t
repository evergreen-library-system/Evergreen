#!perl

use Test::More tests => 2;

diag("Simple tests against the open-ils.storage service and the stock test data.");

use strict; use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();
 
my $ses = $script->session('open-ils.storage');
my $req = $ses->request('open-ils.storage.direct.actor.user.retrieve', 1);
if (my $resp = $req->recv) {
    if (my $user = $resp->content) {
        is(
            ref $user,
            'Fieldmapper::actor::user',
            'open-ils.storage.direct.actor.user.retrieve returned aou object'
        );
        is(
            $user->usrname,
            'admin',
            'User with id = 1 is admin user'
        );
    }
}

