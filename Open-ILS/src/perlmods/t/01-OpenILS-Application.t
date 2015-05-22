#!perl -T

use utf8;
use Test::More tests => 12;

BEGIN {
	use_ok( 'OpenILS::Application' );
}

use_ok( 'OpenILS::Application::AppUtils' );
use_ok( 'OpenILS::Application::Booking' );
use_ok( 'OpenILS::Application::Collections' );
use_ok( 'OpenILS::Application::Fielder' );
use_ok( 'OpenILS::Application::PermaCrud' );
use_ok( 'OpenILS::Application::Reporter' );
use_ok( 'OpenILS::Application::ResolverResolver' );
use_ok( 'OpenILS::Application::Serial' );
use_ok( 'OpenILS::Application::SuperCat' );
use_ok( 'OpenILS::Application::Vandelay' );

is(
    OpenILS::Application::AppUtils::entityize(0, 'èöçÇÈÀ'),
    '&#xE8;&#xF6;&#xE7;&#xC7;&#xC8;&#xC0;',
    'entityize: diacritics'
);
