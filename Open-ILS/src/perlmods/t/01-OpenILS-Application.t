#!perl -T

use Test::More tests => 13;

BEGIN {
	use_ok( 'OpenILS::Application' );
}

use_ok( 'OpenILS::Application::AppUtils' );
use_ok( 'OpenILS::Application::Booking' );
use_ok( 'OpenILS::Application::Collections' );
use_ok( 'OpenILS::Application::Fielder' );
use_ok( 'OpenILS::Application::Ingest' );
use_ok( 'OpenILS::Application::Penalty' );
use_ok( 'OpenILS::Application::PermaCrud' );
use_ok( 'OpenILS::Application::Reporter' );
use_ok( 'OpenILS::Application::ResolverResolver' );
use_ok( 'OpenILS::Application::Serial' );
use_ok( 'OpenILS::Application::SuperCat' );
use_ok( 'OpenILS::Application::Vandelay' );
