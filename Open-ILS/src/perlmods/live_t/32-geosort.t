#!perl
use strict; use warnings;
use Test::More tests => 8;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;

diag("test geocoding");

my $U = 'OpenILS::Application::AppUtils';
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $geo_session = $script->session('open-ils.geo');

my $request = $geo_session->request(
    'open-ils.geo.retrieve_coordinates',
    4,
    '30016'
);
my $result = $request->recv();
my $content = $result->content();
is($content->{textcode},'GEOCODING_NOT_ENABLED','received expected GEOCODING_NOT_ENABLED');

my $e = new_editor(xact => 1);
$e->init;

my $flag = $e->retrieve_config_global_flag('opac.use_geolocation');
$flag->enabled('t');
my $stat = $e->update_config_global_flag($flag);
ok($stat, 'opac.use_geolocation enabled');
$e->xact_commit;

$request = $geo_session->request(
    'open-ils.geo.retrieve_coordinates',
    4,
    '30016'
);
$result = $request->recv();
$content = $result->content();
is($content->{textcode},'GEOCODING_NOT_ALLOWED','received expected GEOCODING_NOT_ALLOWED');

$e->xact_begin;
my $cgs = Fieldmapper::config::geolocation_service->new;
$cgs->active('t');
$cgs->owner(1);
$cgs->name('OSM');
$cgs->service_code('OSM');
$stat = $e->create_config_geolocation_service($cgs);
ok($stat, 'Geolocation service created successfully');
$e->xact_commit;

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});

my $authtoken = $script->authtoken;
ok($authtoken, 'Have an authtoken');

my $setting_value = $U->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $authtoken,
    4,
    {'opac.geographic_location_service_for_address', 1}
);
ok(
    ! ref $setting_value,
    'opac.geographic_location_service_for_address set for BR1'
);

$request = $geo_session->request(
    'open-ils.geo.retrieve_coordinates',
    4,
    '30016'
);
$result = $request->recv();
$content = $result->content();
use Data::Dumper;
diag(Dumper($content));
ok(
    $content->{latitude},
    'Result contains latitude'
);
ok(
    $content->{latitude},
    'Result contains longitude'
);
$request->finish();

