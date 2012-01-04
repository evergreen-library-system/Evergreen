#!perl -T

use Test::More tests => 6;

BEGIN {
	use_ok( 'OpenILS::WWW::EGCatLoader' );
}
use_ok( 'OpenILS::WWW::EGCatLoader::Account' );
use_ok( 'OpenILS::WWW::EGCatLoader::Container' );
use_ok( 'OpenILS::WWW::EGCatLoader::Record' );
use_ok( 'OpenILS::WWW::EGCatLoader::Search' );
use_ok( 'OpenILS::WWW::EGCatLoader::Util' );
