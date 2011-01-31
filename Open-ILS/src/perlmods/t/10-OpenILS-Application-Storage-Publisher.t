#!perl -T

use Test::More tests => 11;

BEGIN {
	use_ok( 'OpenILS::Application::Storage::Publisher' );
}

use_ok( 'OpenILS::Application::Storage::Publisher::action' );
use_ok( 'OpenILS::Application::Storage::Publisher::actor' );
use_ok( 'OpenILS::Application::Storage::Publisher::asset' );
use_ok( 'OpenILS::Application::Storage::Publisher::authority' );
use_ok( 'OpenILS::Application::Storage::Publisher::biblio' );
use_ok( 'OpenILS::Application::Storage::Publisher::config' );
use_ok( 'OpenILS::Application::Storage::Publisher::container' );
use_ok( 'OpenILS::Application::Storage::Publisher::metabib' );
use_ok( 'OpenILS::Application::Storage::Publisher::money' );
use_ok( 'OpenILS::Application::Storage::Publisher::permission' );
