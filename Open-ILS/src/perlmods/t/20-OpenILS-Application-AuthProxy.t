#!perl -T

use Test::More tests => 3;

BEGIN {
	use_ok( 'OpenILS::Application::AuthProxy' );
}

use_ok( 'OpenILS::Application::AuthProxy::AuthBase');
use_ok( 'OpenILS::Application::AuthProxy::LDAP_Auth');
