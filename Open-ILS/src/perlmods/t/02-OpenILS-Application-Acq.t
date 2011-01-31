#!perl -T

use Test::More tests => 11;

BEGIN {
	use_ok( 'OpenILS::Application::Acq' );
}

use_ok( 'OpenILS::Application::Acq::Claims ');
use_ok( 'OpenILS::Application::Acq::EDI ');
use_ok( 'OpenILS::Application::Acq::EDI ');
use_ok( 'OpenILS::Application::Acq::Financials ');
use_ok( 'OpenILS::Application::Acq::Invoice ');
use_ok( 'OpenILS::Application::Acq::Lineitem ');
use_ok( 'OpenILS::Application::Acq::Order ');
use_ok( 'OpenILS::Application::Acq::Picklist ');
use_ok( 'OpenILS::Application::Acq::Provider ');
use_ok( 'OpenILS::Application::Acq::Search ');
