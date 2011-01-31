#!perl -T

use Test::More tests => 12;

use_ok( 'OpenILS::WWW::BadDebt' );
use_ok( 'OpenILS::WWW::EGWeb' );
use_ok( 'OpenILS::WWW::Exporter' );
use_ok( 'OpenILS::WWW::IDL2js' );
use_ok( 'OpenILS::WWW::Method' );
use_ok( 'OpenILS::WWW::PasswordReset' );
use_ok( 'OpenILS::WWW::Proxy' );
use_ok( 'OpenILS::WWW::Redirect' );
use_ok( 'OpenILS::WWW::TemplateBatchBibUpdate' );
use_ok( 'OpenILS::WWW::Vandelay' );
use_ok( 'OpenILS::WWW::Web' );
use_ok( 'OpenILS::WWW::XMLRPCGateway' );
