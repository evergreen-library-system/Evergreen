#!perl
use strict; use warnings;

use Test::More tests => 3;

diag("Tests handling of future backdates in checkin");

use constant ITEM_BARCODE => 'CONC4000070';

use DateTime;
use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'
});

ok($script->authtoken, 'Have an authtoken');

my $checkin_resp = $script->do_checkin({
    barcode => ITEM_BARCODE,
    backdate => '3001-01-23' # date of the singularity; it is known.
});

is(ref $checkin_resp,'HASH','Checkin request returned a HASH');

my $ymd = DateTime->now->set_time_zone(DateTime::TimeZone->new( name => "local" ))->strftime('%F');

ok(
    substr($checkin_resp->{payload}->{circ}->checkin_time, 0, 10) eq $ymd,
    'Checkin time matches current date, not backdate'
);

