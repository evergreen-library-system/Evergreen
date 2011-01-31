#!perl -T

use Test::More tests => 4;

BEGIN {
	use_ok( 'OpenILS' );
}

use_ok( 'OpenILS::Const' );
use_ok( 'OpenILS::Event' );
use_ok( 'OpenILS::Perm' );

diag( "Testing OpenILS $OpenILS::VERSION, Perl $], $^X" );
