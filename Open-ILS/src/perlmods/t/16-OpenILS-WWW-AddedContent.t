#!perl -T

use Test::More tests => 5;

BEGIN {
	use_ok( 'OpenILS::WWW::AddedContent' );
}

use_ok( 'OpenILS::WWW::AddedContent::Amazon' );
use_ok( 'OpenILS::WWW::AddedContent::ContentCafe' );
use_ok( 'OpenILS::WWW::AddedContent::OpenLibrary' );
use_ok( 'OpenILS::WWW::AddedContent::Syndetic' );
