#!perl -T

use Test::More tests => 8;

BEGIN {
	use_ok( 'OpenILS::Application::Search' );
}

use_ok( 'OpenILS::Application::Search::AddedContent' );
use_ok( 'OpenILS::Application::Search::Authority' );
use_ok( 'OpenILS::Application::Search::Biblio' );
use_ok( 'OpenILS::Application::Search::CNBrowse' );
use_ok( 'OpenILS::Application::Search::Serial' );
use_ok( 'OpenILS::Application::Search::Z3950' );
use_ok( 'OpenILS::Application::Search::Zips' );
