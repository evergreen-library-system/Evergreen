#!perl -T

use Test::More tests => 4;

BEGIN {
    use_ok( 'OpenILS::Application::EbookAPI' );
    use_ok( 'OpenILS::Application::EbookAPI::Test' );
    use_ok( 'OpenILS::Application::EbookAPI::OverDrive' );
    use_ok( 'OpenILS::Application::EbookAPI::OneClickdigital' );
}

