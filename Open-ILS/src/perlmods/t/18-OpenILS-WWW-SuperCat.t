#!perl -T

use Test::More tests => 10;
use Test::Output;

BEGIN {
	use_ok( 'OpenILS::WWW::SuperCat' );
}
use_ok( 'OpenILS::WWW::SuperCat::Feed' );
use_ok( 'OpenILS::Utils::TagURI' );

my $tag = 'tag::U2@bre/454{holdings_xml}';
my $u = OpenILS::Utils::TagURI->new($tag);
is( $u->id,        454,   'parsed correct ID' );
is( $u->classname, 'bre', 'parsed correct class name' );
is( $u->toURI,     $tag,  'can reconstruct unAPI ID' );

my $apache_stub;
stdout_like { OpenILS::WWW::SuperCat::unapi2_formats($apache_stub, $u) }
            qr/marcxml/,
            'U2 formats list for bre includes marcxml';

stdout_unlike { OpenILS::WWW::SuperCat::unapi2_formats($apache_stub, $u) }
              qr/name="xml"/,
              'U2 formats list for bre does not include xml';

my $u2 = OpenILS::Utils::TagURI->new('tag::U2@acn/4');
stdout_like { OpenILS::WWW::SuperCat::unapi2_formats($apache_stub, $u2) }
            qr/name="xml"/,
            'U2 formats list for acn does includes xml';
stdout_unlike { OpenILS::WWW::SuperCat::unapi2_formats($apache_stub, $u2) }
              qr/name="marcxml"/,
              'U2 formats list for acn does not includes marcxml';
