#!perl -T

use Test::More tests => 12;
use CGI;

BEGIN {
	use_ok( 'OpenILS::WWW::EGCatLoader' );
}
use_ok( 'OpenILS::WWW::EGCatLoader::Account' );
use_ok( 'OpenILS::WWW::EGCatLoader::Container' );
use_ok( 'OpenILS::WWW::EGCatLoader::OpenAthens' );
use_ok( 'OpenILS::WWW::EGCatLoader::Record' );
use_ok( 'OpenILS::WWW::EGCatLoader::Search' );
use_ok( 'OpenILS::WWW::EGCatLoader::Util' );

my $ctx = {};
my $cgi = CGI->new();
$cgi->param('query', 'sort(titlesort) cats site(CONS)');
$cgi->param('sort',  '');
$cgi->param('depth', 0);
my ($user_query, $query, $site, $depth) = OpenILS::WWW::EGCatLoader::_prepare_biblio_search($cgi, $ctx);
is($user_query, 'sort(titlesort) cats site(CONS)', 'LP#100504: user query left as is');
is($site,  'CONS', 'successfully parsed site');
is($depth, '0',    'successfully parsed depth');
is($query,  'cats site(CONS) depth(0)', 'LP#1562153: change sort order to relevance');

# test date filter
$cgi->param('pubdate', 'is');
$cgi->param('date1', '1999');
($user_query, $query, $site, $depth) = OpenILS::WWW::EGCatLoader::_prepare_biblio_search($cgi, $ctx);
is($query, 'date1(1999)  cats site(CONS) depth(0)', 'LP#1005040: "is" pubdate filter mapped to date1() filter');
