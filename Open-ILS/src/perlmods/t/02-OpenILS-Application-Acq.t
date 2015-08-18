#!perl -T

use Test::More tests => 16;

BEGIN {
	use_ok( 'OpenILS::Application::Acq' );
    use_ok( 'OpenILS::Application::Acq::Claims ');
    use_ok( 'OpenILS::Application::Acq::EDI ');
    use_ok( 'OpenILS::Application::Acq::EDI ');
    use_ok( 'OpenILS::Application::Acq::Financials ');
    use_ok( 'OpenILS::Application::Acq::Invoice ');
    use_ok( 'OpenILS::Application::Acq::Lineitem ');
    use_ok( 'OpenILS::Application::Acq::Order ');
    use_ok( 'OpenILS::Application::Acq::Picklist ');
    use_ok( 'OpenILS::Application::Acq::Provider ');
    use_ok( 'OpenILS::Application::Acq::Search ');
}

my $mgr = OpenILS::Application::Acq::BatchManager->new();
is($mgr->throttle(), 4, 'BatchManager throttle is 4 by default');
ok($mgr->exponential_falloff(), 'BatchManager uses exponential falloff by default');
$mgr->total(300);
is($mgr->total(), 300, 'can set total size for BatchManager');
is($mgr->throttle(), 15, 'after setting maximum, BatchManager recalculates throttle');
ok(!($mgr->exponential_falloff()), 'BatchManager does not uses exponential falloff if total set');
