#!perl -T

use Test::More tests => 13;

BEGIN {
	use_ok( 'OpenILS::Application::Storage::CDBI' );
}

use_ok( 'OpenILS::Application::Storage::CDBI::action' );
use_ok( 'OpenILS::Application::Storage::CDBI::actor' );
use_ok( 'OpenILS::Application::Storage::CDBI::asset' );
use_ok( 'OpenILS::Application::Storage::CDBI::authority' );
use_ok( 'OpenILS::Application::Storage::CDBI::biblio' );
use_ok( 'OpenILS::Application::Storage::CDBI::booking' );
use_ok( 'OpenILS::Application::Storage::CDBI::config' );
use_ok( 'OpenILS::Application::Storage::CDBI::container' );
use_ok( 'OpenILS::Application::Storage::CDBI::metabib' );
use_ok( 'OpenILS::Application::Storage::CDBI::money' );
use_ok( 'OpenILS::Application::Storage::CDBI::permission' );
use_ok( 'OpenILS::Application::Storage::CDBI::serial' );
