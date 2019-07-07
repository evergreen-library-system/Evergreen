#!perl -T

use Test::More tests => 6;

use_ok( 'OpenILS::Application::Storage::Driver::Pg' );
use_ok( 'OpenILS::Application::Storage::Driver::Pg::cdbi' );
use_ok( 'OpenILS::Application::Storage::Driver::Pg::fts' );
use_ok( 'OpenILS::Application::Storage::Driver::Pg::storage' );
use_ok( 'OpenILS::Application::Storage::Driver::Pg::dbi' );
use_ok( 'OpenILS::Application::Storage::Driver::Pg::QueryParser' );
