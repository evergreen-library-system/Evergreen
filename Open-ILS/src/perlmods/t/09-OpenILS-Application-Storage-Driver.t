#!perl -T

use Test::More tests => 3;

use_ok( 'OpenILS::Application::Storage::Driver::Pg::cdbi' );
use_ok( 'OpenILS::Application::Storage::Driver::Pg::fts' );
use_ok( 'OpenILS::Application::Storage::Driver::Pg::QueryParser' );

# These modules are not meant to be loaded as a normal Perl module
# use_ok( 'OpenILS::Application::Storage::Driver::Pg' );
# use_ok( 'OpenILS::Application::Storage::Driver::Pg::dbi' );
# use_ok( 'OpenILS::Application::Storage::Driver::Pg::storage' );
