#!perl -T

use Test::More tests => 6;

BEGIN {
	use_ok( 'OpenILS::Application::Cat' );
}

use_ok( 'OpenILS::Application::Cat::AssetCommon' );
use_ok( 'OpenILS::Application::Cat::AuthCommon' );
use_ok( 'OpenILS::Application::Cat::Authority' );
use_ok( 'OpenILS::Application::Cat::BibCommon' );
use_ok( 'OpenILS::Application::Cat::Merge' );
