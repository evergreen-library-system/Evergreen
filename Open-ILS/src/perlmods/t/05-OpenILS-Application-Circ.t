#!perl -T

use Test::More tests => 12;

BEGIN {
	use_ok( 'OpenILS::Application::Circ' );
}

use_ok( 'OpenILS::Application::Circ::CircCommon' );
use_ok( 'OpenILS::Application::Circ::Circulate' );
use_ok( 'OpenILS::Application::Circ::CopyLocations' );
use_ok( 'OpenILS::Application::Circ::CreditCard' );
use_ok( 'OpenILS::Application::Circ::HoldNotify' );
use_ok( 'OpenILS::Application::Circ::Holds' );
use_ok( 'OpenILS::Application::Circ::Money' );
use_ok( 'OpenILS::Application::Circ::NonCat' );
use_ok( 'OpenILS::Application::Circ::StatCat' );
use_ok( 'OpenILS::Application::Circ::Survey' );
use_ok( 'OpenILS::Application::Circ::Transit' );
