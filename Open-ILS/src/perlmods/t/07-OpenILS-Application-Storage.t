#!perl -T

use Test::More tests => 3;

BEGIN {
	use_ok( 'OpenILS::Application::Storage' );
}

use_ok( 'OpenILS::Application::Storage::FTS' );
use_ok( 'OpenILS::Application::Storage::QueryParser' );
