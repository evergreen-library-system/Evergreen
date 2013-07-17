#!perl

use Test::More tests => 2;

diag("Simple tests against the open-ils.storage service and the stock test data.");

use strict; use warnings;
use OpenSRF::System;
use OpenSRF::AppSession;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;

my $config = `osrf_config --sysconfdir`;
chomp $config;
$config .= '/opensrf_core.xml';

OpenSRF::System->bootstrap_client(config_file => $config);
Fieldmapper->import(IDL =>
    OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
 
my $ses = OpenSRF::AppSession->create('open-ils.storage');
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

