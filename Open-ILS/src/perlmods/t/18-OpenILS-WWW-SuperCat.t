#!perl -T

use Test::More tests => 2;

BEGIN {
	use_ok( 'OpenILS::WWW::SuperCat' );
}
use_ok( 'OpenILS::WWW::SuperCat::Feed' );
