#!/usr/bin/perl
require '../oils_header.pl';
use warnings;
use strict;
use OpenILS::Application::Storage::Driver::Pg::QueryParser;
use JSON::XS;
use Getopt::Long;
use Data::Dumper;
$Data::Dumper::Indent = 1;
use Time::HiRes qw/time/;
use OpenILS::Utils::CStoreEditor;

OpenILS::Application::Storage::Driver::Pg::QueryParser->TEST_SETUP;

my $query = '#available title: foo bar* || (-baz || (subject:"1900'.
                        '-1910 junk" "and another thing" se:stuff #available '.
                        'statuses(0,7,12))) && && && au:malarky || au|'.
                        'corporate|personal:gonzo && dc.identifier:+123456789X'.
                        ' dc.contributor=rowling #metarecord estimation_'.
                        'strategy(exclusion) item_type(a, t) item_form(d) '.
                        'bib.subjectTitle=potter bib.subjectName=harry '.
                        'keyword|mapscale:1:250000';

#$query = 'concerto #available filter_group_entry(1,2,3) filter_group_entry(4,5)';
#$query = 'concerto || filter_group_entry(4) || filter_group_entry(3)';
#$query = 'concerto (audience(a) || (item_type(a) && item_form(b)))';
#$query = 'concerto || (piano && (item_type(a) || audience(a)))';

#$query = '(concerto item_type(a)) || (piano item_type(b))';
#$query = 'audience(a) (concerto || item_type(a) || (piano music item_form(b)))';
#$query = 'concerto && (item_type(a) || piano) && (item_form(b) || music)';
$query = 'concerto && (piano || item_type(a)) && (music || item_form(b))';

my $superpage = 1;
my $superpage_size = 1000;
my $core_limit = 25000;
my $debug;
my $config = '/openils/conf/opensrf_core.xml';
my $quiet = 0;

GetOptions(
    'superpage=i' => \$superpage,
    'superpage-size=i' => \$superpage_size,
    'core-limit=i' => \$core_limit,
    'query=s' => \$query,
    'debug' => \$debug,
    'quiet' => \$quiet,
    'config=s' => \$config
);

osrf_connect($config);

my $parser = OpenILS::Application::Storage::Driver::Pg::QueryParser->new( 
    superpage_size => $superpage_size, 
    superpage => $superpage, 
    core_limit => $core_limit, 
    query => $query, 
    debug => $debug 
);

# load the parser config
my $cstore = OpenSRF::AppSession->create( 'open-ils.cstore' );
$parser->initialize(
    config_record_attr_index_norm_map =>
        $cstore->request(
            'open-ils.cstore.direct.config.record_attr_index_norm_map.search.atomic',
            { id => { "!=" => undef } },
            { flesh => 1, flesh_fields => { crainm => [qw/norm/] }, order_by => [{ class => "crainm", field => "pos" }] }
        )->gather(1),
    search_relevance_adjustment         =>
        $cstore->request(
            'open-ils.cstore.direct.search.relevance_adjustment.search.atomic',
            { id => { "!=" => undef } }
        )->gather(1),
    config_metabib_field                =>
        $cstore->request(
            'open-ils.cstore.direct.config.metabib_field.search.atomic',
            { id => { "!=" => undef } }
        )->gather(1),
    config_metabib_search_alias         =>
        $cstore->request(
            'open-ils.cstore.direct.config.metabib_search_alias.search.atomic',
            { alias => { "!=" => undef } }
        )->gather(1),
    config_metabib_field_index_norm_map =>
        $cstore->request(
            'open-ils.cstore.direct.config.metabib_field_index_norm_map.search.atomic',
            { id => { "!=" => undef } },
            { flesh => 1, flesh_fields => { cmfinm => [qw/norm/] }, order_by => [{ class => "cmfinm", field => "pos" }] }
        )->gather(1),
    config_record_attr_definition       =>
        $cstore->request(
            'open-ils.cstore.direct.config.record_attr_definition.search.atomic',
            { name => { "!=" => undef } }
        )->gather(1),
);

$parser->parse;

print "Parsed query tree:\n" . Dumper($parser->parse_tree) unless $quiet;

my $sql = $parser->toSQL;
$sql =~ s/^\s*$//gm;
print "SQL:\n$sql\n\n" unless $quiet;

