#!perl -T

use Test::More tests => 11;

use_ok( 'OpenILS::WWW::BadDebt' );
use_ok( 'OpenILS::WWW::EGWeb' );
use_ok( 'OpenILS::WWW::Exporter' );
use_ok( 'OpenILS::WWW::IDL2js' );
use_ok( 'OpenILS::WWW::Proxy' );
use_ok( 'OpenILS::WWW::Redirect' );
use_ok( 'OpenILS::WWW::TemplateBatchBibUpdate' );
use_ok( 'OpenILS::WWW::Vandelay' );
use_ok( 'OpenILS::WWW::XMLRPCGateway' );

is( OpenILS::WWW::EGWeb::parse_eg_locale('hy_am'), 'hy-AM', 'correctly formatted Armenian language code' );
is( OpenILS::WWW::EGWeb::parse_eg_locale(), 'en-US', 'correctly formatted default language code' );
