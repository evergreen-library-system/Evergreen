#!perl
use strict; use warnings;
use Test::More tests => 12;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;

diag("test geocoding");

my $U = 'OpenILS::Application::AppUtils';
my $script = OpenILS::Utils::TestUtils->new();

# point in Oregon
my $lat1 = 45.68241;
my $long1 = -121.77216;

# point in Massachusetts
my $lat2 = 42.05623;
my $long2 = -71.469374;

# point in North Carolina
my $lat3 = 35.7829276803131;
my $long3 = -78.63741562428143;

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
    $content->{longitude},
    'Result contains longitude'
);
$request->finish();

# get the distance between Oregon and Massachusetts 
$request = $geo_session->request(
    'open-ils.geo.calculate_distance',
    [$lat1, $long1],
    [$lat2, $long2]
);
$result = $request->recv();
$content = $result->content();
diag(Dumper($content));
is(
    int($content),
    3990,
    "Distance between Oregon and Massachusetts is ~3990km"
);

# give the concerto org addresses long/lat

$e->xact_begin;

# place br1 in Oregon
my $br1_addrs = $e->search_actor_org_address({org_unit => 4});
foreach(@$br1_addrs){
    $_->longitude($long1);
    $_->latitude($lat1);
    $e->update_actor_org_address($_);
}

# place br2 in Massachusetts
my $br2_addrs = $e->search_actor_org_address({org_unit => 5});
foreach(@$br2_addrs){
    $_->longitude($long2);
    $_->latitude($lat2);
    $e->update_actor_org_address($_);
}

$e->xact_commit;

$request = $geo_session->request(
    'open-ils.geo.sort_orgs_by_distance_from_coordinate',
    [$lat3, $long3],
    [4,5]
);
$result = $request->recv();
$content = $result->content();
diag(Dumper($content));
is(
    $content->[0],
    5,
    "North Carolina is closer to Massachusetts than Oregon"
);

$request = $geo_session->request(
    'open-ils.geo.sort_orgs_by_distance_from_coordinate.include_distances',
    [$lat3, $long3],
    [4,5]
);
$result = $request->recv();
$content = $result->content();
diag(Dumper($content));
is(
    $content->[0]->[0],
    5,
    "North Carolina is closer to Massachusetts than Oregon"
);

is(
    int($content->[0]->[1]),
    933,
    "North Carolina is ~933km from Massachusetts"
);
