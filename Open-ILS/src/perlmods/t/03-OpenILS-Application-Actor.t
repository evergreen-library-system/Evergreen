#!perl -T

use Test::More tests => 6;

BEGIN {
	use_ok( 'OpenILS::Application::Actor' );
}

use_ok( 'OpenILS::Application::Actor::ClosedDates' );
use_ok( 'OpenILS::Application::Actor::Container' );
use_ok( 'OpenILS::Application::Actor::Friends' );
use_ok( 'OpenILS::Application::Actor::Stage' );
use_ok( 'OpenILS::Application::Actor::UserGroups' );
