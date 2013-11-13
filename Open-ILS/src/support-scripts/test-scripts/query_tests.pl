#!/usr/bin/perl
require '../oils_header.pl';
use strict; use warnings;
use OpenSRF::EX qw(:try);
use OpenSRF::AppSession;
use Getopt::Long;
use Data::Dumper;

my $config = '/openils/conf/opensrf_core.xml';
my $debug = 0;
my @default_queries = (
    'keyword1',
    'keyword1 || keyword2',
    '(keyword1) || keyword2',
    'keyword1 || (keyword2)',
    '(keyword1) || (keyword2)',
    'keyword item_type(a)',
    '(item_type(a)) keyword1',
    'keyword1 item_type(a) title:keyword2',
    'keyword1 (item_type(a)) title:keyword2',
    'item_type(a) keyword1 title:keyword2',
    '(item_type(a)) keyword1 title:keyword2',
    'concerto',
    'concerto (violin || piano)',
    '-keyword1',
    '-"keyword1"',
    'keyword:"keyword1"',
    'keyword:"keyword1" title:"keyword2"',
    'keyword locations() statuses()',
# A small set of searches that errored out in a production install
    'keyword: subject:Graphical user interfaces (Computer systems) depth(0) subject|topic[Authoring programs]',
    'keyword: subject:Assassins New York (State) depth(0) subject|geographic[Buffalo (N.Y.)]',
    'keyword: author: Niggeman Indifilm (Firm) depth(0) subject|geographic[Mars (Planet)]',
    'keyword: subject:Los Angeles (Calif.) Juvenile fiction. depth(0) subject|geographic[Los Angeles (Calif.)]',
    'keyword: subject:Los Angeles (Calif.) depth(0) subject|geographic[California] subject|name[Faulkner, William 1897-1962]',
    'keyword: subject:Thrillers (Motion pictures, television, etc.) depth(0) subject|topic[Action and adventure films]',
    'keyword: author: Brilliance Audio (Firm) depth(0) subject|topic[Man-woman relationships]',
    'keyword: subject:Rhodenbarr, Bernie (Fictitious character) depth(0) subject|geographic[England] subject|topic[Audiocassettes]',
    'keyword: subject:Burgett, Donald R. (Donald Robert), depth(0) subject|geographic[Netherlands]',
    'keyword: author: 2 Entertain (Firm) depth(0) subject|geographic[England] subject|geographic[Nottingham (England)]',
# Selection from the query_parser.pl script
    '#available title: foo bar* || (-baz || (subject:"1900'.
                        '-1910 junk" "and another thing" se:stuff #available '.
                        'statuses(0,7,12))) && && && au:malarky || au|'.
                        'corporate|personal:gonzo && dc.identifier:+123456789X'.
                        ' dc.contributor=rowling #metarecord estimation_'.
                        'strategy(exclusion) item_type(a, t) item_form(d) '.
                        'bib.subjectTitle=potter bib.subjectName=harry '.
                        'keyword|mapscale:1:250000',
    'concerto #available filter_group_entry(1,2,3) filter_group_entry(4,5)',
    'concerto || filter_group_entry(4) || filter_group_entry(3)',
    'concerto (audience(a) || (item_type(a) && item_form(b)))',
    'concerto || (piano && (item_type(a) || audience(a)))',
    '(concerto item_type(a)) || (piano item_type(b))',
    'audience(a) (concerto || item_type(a) || (piano music item_form(b)))',
    'concerto && (item_type(a) || piano) && (item_form(b) || music)',
    'concerto && (piano || item_type(a)) && (music || item_form(b))',
    'Cancer du sujet {circ}ag{acute}e',
    'a || b || c || d || e || f || g || h || i || j || k || l || m || n || o || p || q || r || s || t || u || v || w || x || y || z', # will run afoul of depth restrictions 

);

my @queries;

GetOptions(
    'config=s' => \$config,
    'debug' => \$debug,
    'query=s' => \@queries,
);
osrf_connect($config); # connect to jabber

@queries = @default_queries unless @queries;

my $ses = OpenSRF::AppSession->create("open-ils.search");
$ses->connect;
print "Running Queries\n";
foreach (@queries) {
    try {
        my $req = $ses->request('open-ils.search.biblio.multiclass.query', {}, $_, 0);
        my $stat = $req->gather(1);
        print "Query $_ returned " . $stat->{count} . " results\n";
    } catch Error with {
        print "ERROR ON QUERY: $_\n";
    };
}
print "Done\n";
$ses->disconnect;


