#!perl -T

use Test::More tests => 9;

BEGIN {
	use_ok( 'OpenILS::WWW::AddedContent' );
}

use_ok( 'OpenILS::WWW::AddedContent::Amazon' );
use_ok( 'OpenILS::WWW::AddedContent::ContentCafe' );
use_ok( 'OpenILS::WWW::AddedContent::OpenLibrary' );
use_ok( 'OpenILS::WWW::AddedContent::Syndetic' );

my $amazon = OpenILS::WWW::AddedContent::Amazon;
is($amazon->normalize_key('9791186178140'), '9791186178140', 'Amazon Added Content can handle 979 ISBNs');
is($amazon->normalize_key('9780735220171'), '0735220174', 'Amazon Added Content converts ISBN-13s to ISBN-10s');
is($amazon->normalize_key('0735220174'), '0735220174', 'Amazon Added Content leaves ISBN-10s as they are');
is($amazon->normalize_key('978-0735220171'), '0735220174', 'Amazon Added Content removes hyphens from ISBNs');
