#!perl -T

use Test::More tests => 9;
use CGI;

BEGIN {
	use_ok( 'OpenILS::WWW::EGCatLoader' );
}
use_ok( 'OpenILS::WWW::EGCatLoader::Account' );
use_ok( 'OpenILS::WWW::EGCatLoader::Container' );
use_ok( 'OpenILS::WWW::EGCatLoader::Record' );
use_ok( 'OpenILS::WWW::EGCatLoader::Search' );
use_ok( 'OpenILS::WWW::EGCatLoader::Util' );

my $ctx = {};
my $cgi = CGI->new();
$cgi->param('query', 'sort(titlesort) cats site(CONS)');
$cgi->param('sort',  '');
$cgi->param('depth', 0);
my ($new_query, $site, $depth) = OpenILS::WWW::EGCatLoader::_prepare_biblio_search($cgi, $ctx);
is($site,  'CONS', 'successfully parsed site');
is($depth, '0',    'successfully parsed depth');
is($new_query,  'cats site(CONS) depth(0)', 'LP#1562153: change sort order to relevance');
