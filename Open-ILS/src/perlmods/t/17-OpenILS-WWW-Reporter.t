#!perl -T

use Test::More tests => 2;

BEGIN {
	use_ok( 'OpenILS::WWW::Reporter' );
}
use_ok( 'OpenILS::WWW::Reporter::transforms' );
