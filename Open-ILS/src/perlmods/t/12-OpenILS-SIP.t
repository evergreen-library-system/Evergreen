#!perl -T

use Test::More tests => 8;

BEGIN {
	use_ok( 'OpenILS::SIP' );
}

use_ok( 'OpenILS::SIP::Item' );
use_ok( 'OpenILS::SIP::Msg' );
use_ok( 'OpenILS::SIP::Patron' );
use_ok( 'OpenILS::SIP::Transaction' );
use_ok( 'OpenILS::SIP::Transaction::Checkin' );
use_ok( 'OpenILS::SIP::Transaction::Checkout' );
use_ok( 'OpenILS::SIP::Transaction::Renew' );
