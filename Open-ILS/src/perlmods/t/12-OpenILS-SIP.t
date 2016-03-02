#!perl
# note that taint mode is explicitly off; see
# https://rt.cpan.org/Public/Bug/Display.html?id=94520 for why

use Test::More tests => 9;

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

$ENV{TZ} = 'America/New_York'; # chosen to exercise the LP#1516757 bug
my $dob = '1960-12-31';
my $dob_formatted = OpenILS::SIP->format_date($dob, 'dob');
is($dob_formatted, '19601231', 'LP#1516757: ensure dates of birth do not get offset');
