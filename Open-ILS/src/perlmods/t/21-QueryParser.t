#!perl

use strict;
use warnings; # FATAL => qw(all);
use Test::More;

BEGIN {
	use_ok( 'OpenILS::Application::Storage::QueryParser' );
#    use_ok( 'OpenILS::Application::Storage::Driver::Pg::QueryParser' );
}

my %args = ( debug => 0 );
my $QParser = QueryParser->new(%args);
is(ref $QParser, 'QueryParser', 'Created QueryParser');
is($QParser->operator('and'), '&&', 'Expected and operator');

$Data::Dumper::Indent = 1;

$QParser->add_search_class_alias( keyword => 'kw' );
is ($QParser->search_class_count, 1, "Added one search class");
init_qp();

is ($QParser->search_class_count, 5, "Correct number of search classes");
is (scalar(@{$QParser->search_fields()->{'author'}}), 3, "Correct number of search fields for 'author' class");
$QParser->remove_search_field('author', 'personal');
is (scalar(@{$QParser->search_fields()->{'author'}}), 2, "Removed search field");
$QParser->remove_search_class('title');
is ($QParser->search_class_count, 4, "Removed search class");
is (scalar(@{$QParser->search_class_aliases->{'author'}}), 3, "Correct number of aliases for 'author' class");
$QParser->remove_search_class_alias( author => 'au' );
is (scalar(@{$QParser->search_class_aliases->{'author'}}), 2, "Removed alias for 'author' class");
is (scalar(@{$QParser->search_field_aliases->{'subject'}->{'name'}}), 2, "Correct number of search field aliases for 'subject' class");
$QParser->remove_search_field_alias( subject => name => 'nomen' );
is (scalar(@{$QParser->search_field_aliases->{'subject'}->{'name'}}), 1, "Removed search field alias");

is ($QParser->facet_class_count, 2, "Correct number of facet classes");
is (scalar(@{$QParser->facet_fields()->{'author'}}), 2, "Correct number of facet fields for 'author' class");
$QParser->remove_facet_field('author', 'personal');
is (scalar(@{$QParser->facet_fields()->{'author'}}), 1, "Removed facet field");
$QParser->remove_facet_class('author');
is ($QParser->facet_class_count, 1, "Removed facet class");

is ($QParser->filter_count, 29, "Correct number of filters");
is (scalar(@{$QParser->filter_normalizers('skip_check')}), 0, 'No filter normalizers by default');
$QParser->add_filter_normalizer('skip_check', \&test_filter_norm);
is (scalar(@{$QParser->filter_normalizers('skip_check')}), 1, 'Added filter normalizer');
is ($QParser->modifier_count, 8, "Correct number of modifiers");

is_deeply ($QParser->custom_data('string'), { }, "No custom data set for 'string'");

is($QParser->core_limit(25000), 25000, 'Core limit setting works');
is($QParser->core_limit(), 25000, 'Core limit stays set');

is($QParser->superpage(1), 1, 'Superpage setting works');
is($QParser->superpage(), 1, 'Superpage stays set');

# see QueryParser.pm, this won't work:
# is($QParser->superpage(0), 0, 'Superpage can be unset');

is($QParser->superpage_size(1000), 1000, 'Superpage size setting works');
is($QParser->superpage_size(), 1000, 'Superpage size stays set');

init_qp();
eval {
    local $SIG{ALRM} = sub { die "timed out!\n" };
    alarm 1;
    $QParser->parse('-"unclosed phrase');
};
if ($@) {
    fail('parsing modified unclosed phrase query timed out');
} else {
    pass('successfully parsed modified unclosed phrase query');
}

# It's unfortunate not to be able to use the following tests immediately, but
# they reflect assumptions that need to be updated in light of new qp_fix code.
# Also,, canonicalization may not preserve insignificant whitespace nor the
# exact, original number of non-semantic parentheses.

=cut

init_qp();

my %queries = (
    '(keyword1 keyword2) || keyword3' => undef,
    'keyword1 || keyword2' => undef,
    'author:keyword1 keyword2' => undef,
    '(keyword1) || (keyword2)' => undef,
    'keyword1 || keyword2 || keyword3' => undef,
    '(keyword1 || keyword2) && keyword3' => undef,
    'keyword1 keyword2 || keyword3 keyword4' => sub {
        my $query = shift;
        # Unfortunately, the canonical representation of a query in master
        # as of 2012/09/07 is not unambiguous
        is($QParser->parse_tree()->to_abstract_query()->{children}->{'&'}, undef, "Outer-most operator in query {$query} is not AND");
        is(ref $QParser->parse_tree()->to_abstract_query()->{children}->{'|'}, 'ARRAY', "Outer-most operator in query {$query} is OR");
    },
    'keyword1 keyword2 && keyword3 keyword4' => undef,
    'keyword1 author:keyword2' => undef,
    'au:keyword1 kw:keyword2' => undef,
    'keyword1 pref_ou(lib)' => sub {
        my $query = shift;
        is($QParser->parse_tree->to_abstract_query()->{filters}->[0]->{name}, 'pref_ou', 'Generated filter for query');
    },
    'keyword1 #available' => sub {
        my $query = shift;
        is($QParser->parse_tree->to_abstract_query()->{modifiers}->[0], 'available', 'Set modifier for query');
    },
    '(keyword1 keyword2) || keyword3 #available' => sub {
        my $query = shift;
        is($QParser->parse_tree->to_abstract_query()->{modifiers}->[0], 'available', 'Set modifier for query');
    },
    'keyword1 testfilter(whatever)' => undef,
    'keyword1 sort:something' => undef,
    '"phrase1 phrase2" keyword1' => undef, # NOTE: phrases do not have a stable canonical representation, 2012-09-09
    'keyword1 -keyword2' => undef,
    'keyword1 +keyword2' => undef,
);

my $query;
my $testfunc;
while (($query, $testfunc) = each (%queries)) {
    init_qp();
    $QParser->parse($query);
    # TODO: Test initial parse
    &$testfunc($query) if ($testfunc);
    my $canonical = clean(QueryParser::Canonicalize::abstract_query2str_impl($QParser->parse_tree()->to_abstract_query()));
    $canonical = reparse($canonical);
    init_qp();
    $QParser->parse($canonical);
    is(clean(QueryParser::Canonicalize::abstract_query2str_impl($QParser->parse_tree()->to_abstract_query())), $canonical, "Building query from canonical query is idempotent for query {$query}");
}

my %equivalences = (
    'keyword1 keyword2' => 'keyword1 && keyword2',
    'keyword1 keyword2 || keyword3 keyword4' => 'keyword1 && keyword2 || keyword3 && keyword4',
    'keyword1 keyword2 || keyword3 keyword4' => '(keyword1 keyword2) || (keyword3 keyword4)',
    'keyword1 keyword2 && keyword3 keyword4' => '(keyword1 && keyword2) && (keyword3 && keyword4)',
    'keyword1 || && keyword2' => 'keyword1 || keyword2',
    'keyword1' => 'keyword:keyword1',
);

my $equivalent;
while (($query, $equivalent) = each (%equivalences)) {
    init_qp();
    $QParser->parse($query);
    my $canonical1 = reparse(clean(QueryParser::Canonicalize::abstract_query2str_impl($QParser->parse_tree()->to_abstract_query())));
    init_qp();
    $QParser->parse($equivalent);
    my $canonical2 = reparse(clean(QueryParser::Canonicalize::abstract_query2str_impl($QParser->parse_tree()->to_abstract_query())));
    is($canonical1, $canonical2, "Queries {$query} and {$equivalent} are equivalent");
}

my %differences = (
    '(keyword1 keyword2) || keyword3' => 'keyword1 && (keyword2 || keyword3)',
    'keyword1 || (keyword2 && keyword3)' => '(keyword1 || keyword2) && keyword3',
    '(keyword1 || keyword2) && keyword3' => 'keyword1 || (keyword2 && keyword3)',
    'keyword1 keyword2 || keyword3 keyword4' => '(keyword1 keyword2 || keyword3) keyword4', # this should fail on master, 2012-09-07
);


my $different;
while (($query, $different) = each (%differences)) {
    init_qp();
    $QParser->parse($query);
    my $canonical1 = reparse(clean(QueryParser::Canonicalize::abstract_query2str_impl($QParser->parse_tree()->to_abstract_query())));
    init_qp();
    $QParser->parse($different);
    my $canonical2 = reparse(clean(QueryParser::Canonicalize::abstract_query2str_impl($QParser->parse_tree()->to_abstract_query())));
    isnt($canonical1, $canonical2, "Queries {$query} and {$different} are not equivalent");
}

=cut

done_testing;

sub test_filter_norm {
    return;
}

sub test_filter_callback {
    my ($QParser, $struct, $filter, $params, $negate) = @_;
    is($filter, 'testfilter', 'Filter callback on correct filter');
    return;
}

sub clean {
    my $string = shift;
    $string =~ s/\s+/ /g;
    $string =~ s/ \)/\)/g;
    $string =~ s/\( /\(/g;
    $string =~ s/ $//g;
    $string =~ s/^ //g;
    
    ($string, undef) = parse_parens($string);

    $string =~ s/(^| )\(([^) ]+)\)/$2/g;
    $string =~ s/^\(([^)]*)\)$/$1/g;

    return $string;
}

sub parse_parens {
    my $string = shift;
    my $subres;
    my $result = '';
    while (my $nextchar = substr($string, 0, 1)) {
        $string = substr($string, 1);
        if ($nextchar eq '(') {
            ($subres, $string) = parse_parens($string);
            if ($result || ! (substr($string, 0, 1) eq ')')) {
                $result .= "($subres)";
            } else {
                $result = $subres;
            }
        } elsif ($nextchar eq ')') {
            return ($result, $string);
        } else {
            $result .= $nextchar;
        }
    }
    return $result;
}

sub reparse {
    my $canonical = shift;
    my $repeats = $canonical =~ tr/&/&/;
    $repeats = ($repeats / 2) + 1;
    my $result;
    while (--$repeats) {
        init_qp();
        $QParser->parse($canonical);
        $canonical = clean(QueryParser::Canonicalize::abstract_query2str_impl($QParser->parse_tree()->to_abstract_query()));
    }
    return $canonical;
}

sub init_qp {
    $QueryParser::parser_config{QueryParser}->{allow_nested_modifiers} = 1;
    $QParser = QueryParser->new(%args);
    $QParser->add_search_class_alias( title => 'ti' );
    $QParser->add_search_class_alias( author => 'au' );
    $QParser->add_search_class_alias( author => 'name' );
    $QParser->add_search_class_alias( author => 'dc.contributor' );
    $QParser->add_search_class_alias( subject => 'su' );
    $QParser->add_search_class_alias( subject => 'bib.subject(?:Title|Place|Occupation)' );
    $QParser->add_search_class_alias( series => 'se' );
    $QParser->add_search_class_alias( keyword => 'dc.identifier' );

    $QParser->add_query_normalizer( author => corporate => 'search_normalize' );
    $QParser->add_query_normalizer( keyword => keyword => 'search_normalize' );
    
    $QParser->add_search_field_alias( subject => name => 'bib.subjectName' );
    $QParser->add_search_field_alias( subject => name => 'nomen' );

    $QParser->add_search_field( 'author' => 'personal' );
    $QParser->add_search_field( 'author' => 'corporate' );
    $QParser->add_search_field( 'author' => 'meeting' );

    $QParser->default_search_class( 'keyword' );

    # will be retained simply for back-compat
    $QParser->add_search_filter( 'format' );

    # grumble grumble, special cases against date1 and date2
    $QParser->add_search_filter( 'before' );
    $QParser->add_search_filter( 'after' );
    $QParser->add_search_filter( 'between' );
    $QParser->add_search_filter( 'during' );

    # used by layers above this
    $QParser->add_search_filter( 'statuses' );
    $QParser->add_search_filter( 'locations' );
    $QParser->add_search_filter( 'location_groups' );
    $QParser->add_search_filter( 'site' );
    $QParser->add_search_filter( 'pref_ou' );
    $QParser->add_search_filter( 'lasso' );
    $QParser->add_search_filter( 'my_lasso' );
    $QParser->add_search_filter( 'depth' );
    $QParser->add_search_filter( 'language' );
    $QParser->add_search_filter( 'offset' );
    $QParser->add_search_filter( 'limit' );
    $QParser->add_search_filter( 'check_limit' );
    $QParser->add_search_filter( 'skip_check' );
    $QParser->add_search_filter( 'superpage' );
    $QParser->add_search_filter( 'estimation_strategy' );
    $QParser->add_search_filter( 'copy_tag' );
    $QParser->add_search_modifier( 'available' );
    $QParser->add_search_modifier( 'staff' );

    # Start from container data (bre, acn, acp): container(bre,bookbag,123,deadb33fdeadb33fdeadb33fdeadb33f)
    $QParser->add_search_filter( 'container' );

    # Start from a list of record ids, either bre or metarecords, depending on the #metabib modifier
    $QParser->add_search_filter( 'record_list' );

    # used internally, but generally not user-settable
    $QParser->add_search_filter( 'preferred_language' );
    $QParser->add_search_filter( 'preferred_language_weight' );
    $QParser->add_search_filter( 'preferred_language_multiplier' );
    $QParser->add_search_filter( 'core_limit' );

    # XXX Valid values to be supplied by SVF
    $QParser->add_search_filter( 'sort' );

    # modifies core query, not configurable
    $QParser->add_search_modifier( 'descending' );
    $QParser->add_search_modifier( 'ascending' );
    $QParser->add_search_modifier( 'nullsfirst' );
    $QParser->add_search_modifier( 'nullslast' );
    $QParser->add_search_modifier( 'metarecord' );
    $QParser->add_search_modifier( 'metabib' );

    $QParser->add_facet_field( 'author' => 'personal' );
    $QParser->add_facet_field( 'author' => 'corporate' );
    $QParser->add_facet_field( 'subject' => 'topic' );
    $QParser->add_facet_field( 'subject' => 'geographic' );

    $QParser->add_search_filter( 'testfilter', \&test_filter_callback );
}
