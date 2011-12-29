#!/usr/bin/perl
use warnings;
use strict;
use OpenILS::Application::Storage::Driver::Pg::QueryParser;
use JSON::XS;
use Getopt::Long;
use Data::Dumper;
$Data::Dumper::Indent = 1;
use Time::HiRes qw/time/;

OpenILS::Application::Storage::Driver::Pg::QueryParser->TEST_SETUP;

my $query = '#available title: foo bar* || (-baz || (subject:"1900'.
                        '-1910 junk" "and another thing" se:stuff #available '.
                        'statuses(0,7,12))) && && && au:malarky || au|'.
                        'corporate|personal:gonzo && dc.identifier:+123456789X'.
                        ' dc.contributor=rowling #metarecord estimation_'.
                        'strategy(exclusion) item_type(a, t) item_form(d) '.
                        'bib.subjectTitle=potter bib.subjectName=harry '.
                        'keyword|mapscale:1:250000';
my $superpage = 1;
my $superpage_size = 1000;
my $core_limit = 25000;
my $debug;
my $quiet;
my $runs = 100;

GetOptions(
    'superpage=i' => \$superpage,
    'superpage-size=i' => \$superpage_size,
    'core-limit=i' => \$core_limit,
    'query=s' => \$query,
    'debug' => \$debug,
    'quiet' => \$quiet,
    'runs=i' => \$runs
);

print "Original query: $query\n";

my $start = time();
OpenILS::Application::Storage::Driver::Pg::QueryParser->new( superpage_size => $superpage_size, superpage => $superpage, core_limit => $core_limit, debug => $debug, query => $query )->parse->parse_tree for (1 .. $runs);
my $end = time();

my $plan = OpenILS::Application::Storage::Driver::Pg::QueryParser->new( superpage_size => $superpage_size, superpage => $superpage, core_limit => $core_limit, query => $query, debug => $debug );
$plan->parse;
print "Parsed query tree:\n" .  Dumper( $plan->parse_tree) if (!$quiet);
#print "Parsed query tree:\n" .  Dumper( QueryParser->new( superpage_size => $superpage_size, superpage => $superpage, core_limit => $core_limit, query => $query, debug => $debug )->parse->parse_tree);
my $sql = $plan->toSQL;
$sql =~ s/^\s*$//gm;
print "SQL:\n$sql\n\n" if (!$quiet);

my $abstract_query = $plan->parse_tree->to_abstract_query(with_config => 1);
print "abstract_query: " . Dumper($abstract_query) . "\n";
print "Simple plan: " . ($plan->simple_plan ? 'yes' : 'no') . "\n"; 
print "Total parse time, $runs runs: " . ($end - $start) . "s\n";
print "Average parse time, $runs runs: " . sprintf('%0.3f',(($end - $start) / $runs) * 1000) . "ms\n";

