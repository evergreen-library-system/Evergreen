#!perl
use strict; use warnings;
use Test::More tests => 11;
use OpenILS::WWW::EGCatLoader;

use_ok('OpenILS::WWW::EGCatLoader');
can_ok( 'OpenILS::WWW::EGCatLoader', '_create_where_clause' );

my $orgs = (1..9);

my @course_name_query = {'qtype' => 'name','contains' => 'contains','bool' => 'and','value' => 'zebra'};
my $course_name_expected = {"-and" => [
                               {"owning_lib"=> $orgs},
                               {"-not"=>{"+acmc"=>"is_archived"}},
                               {"name"=>{"~*"=>"zebra"}}]};
is_query_parsed_correctly ( \@course_name_query, $course_name_expected, 'Create a valid course name search json query' );

my @course_name_wildcard_query = {'qtype' => 'name','contains' => 'contains','bool' => 'and','value' => '*ebra'};
my $course_name_wildcard_expected = {"-and" => [
                               {"owning_lib"=> $orgs},
                               {"-not"=>{"+acmc"=>"is_archived"}},
                               {"name"=>{"~*"=>".*ebra"}}]};
is_query_parsed_correctly ( \@course_name_wildcard_query, $course_name_wildcard_expected, 'Create a valid course name search json query' );

my @empty_number_query = {'qtype' => 'course_number','contains' => 'contains','bool' => 'and','value' => ''};
my $blank_query_expected = {"-and" => [
                               {"owning_lib"=> $orgs},
                               {"-not"=>{"+acmc"=>"is_archived"}}]};
is_query_parsed_correctly ( \@empty_number_query, $blank_query_expected,
                            'Create a valid course number search json query for blank search' );

my @instructor_wildcard_query = {'qtype' => 'instructor','contains' => 'contains','bool' => 'and','value' => '*'};
is_query_parsed_correctly( \@instructor_wildcard_query, $blank_query_expected,
                           'Create a valid instructor search json query for wildcard search' );

my @instructor_blank_query = {'qtype' => 'instructor','contains' => 'contains','bool' => 'and','value' => ''};
is_query_parsed_correctly( \@instructor_blank_query, $blank_query_expected,
                           'Create a valid instructor search json query for blank search' );

my @instructor_query = {'qtype' => 'instructor','contains' => 'contains','bool' => 'and','value' => 'leonard'};
my $instructor_query_expected = {"-and" => [
                                    {"owning_lib"=> $orgs},
                                    {"-not"=>{"+acmc"=>"is_archived"}},
                                    {"id"=>{"in"=>{
                                        "where"=>[
                                            {"+acmr"=>"is_public"},
                                            {"usr"=>{"in"=>
                                                {"select"=>{"au"=>["id"]},
                                                "where"=>{"name_kw_tsvector"=>
                                                {"@@"=>{"value"=>["to_tsquery","leonard"]}}},
                                            "from"=>"au"}}}],                                        
                                        "select"=>{"acmcu"=>["course"]},
                                        "from"=>{"acmcu" => "acmr"}}}}]};
is_query_parsed_correctly( \@instructor_query, $instructor_query_expected,
                           'Create a valid instructor search json query');

my @instructor_query_with_spaces = {'qtype' => 'instructor','contains' => 'contains','bool' => 'and','value' => 'professor gwendolyn davenport'};
my $instructor_query_with_spaces_expected = {"-and" => [
                                                {"owning_lib"=> $orgs},
                                                {"-not"=>{"+acmc"=>"is_archived"}},
                                                {"id"=>{"in"=>{
                                                    "where"=>[
                                                        {"+acmr"=>"is_public"},
                                                        {"usr"=>{"in"=>
                                                            {"select"=>{"au"=>["id"]},
                                                            "where"=>{"name_kw_tsvector"=>
                                                            {"@@"=>{"value"=>["to_tsquery","professor & gwendolyn & davenport"]}}},
                                                        "from"=>"au"}}}],                                        
                                                    "select"=>{"acmcu"=>["course"]},
                                                    "from"=>{"acmcu" => "acmr"}}}}]};
is_query_parsed_correctly( \@instructor_query_with_spaces, $instructor_query_with_spaces_expected,
                           'Add & to the ts_query input in json query');

my @instructor_query_leading_space = {'qtype' => 'instructor','contains' => 'contains','bool' => 'and','value' => ' gwendolyn'};
my $instructor_query_leading_space_expected = {"-and" => [
                                                {"owning_lib"=> $orgs},
                                                {"-not"=>{"+acmc"=>"is_archived"}},
                                                {"id"=>{"in"=>{
                                                    "where"=>[
                                                        {"+acmr"=>"is_public"},
                                                        {"usr"=>{"in"=>
                                                            {"select"=>{"au"=>["id"]},
                                                            "where"=>{"name_kw_tsvector"=>
                                                            {"@@"=>{"value"=>["to_tsquery","gwendolyn"]}}},
                                                        "from"=>"au"}}}],                                        
                                                    "select"=>{"acmcu"=>["course"]},
                                                    "from"=>{"acmcu" => "acmr"}}}}]};
is_query_parsed_correctly( \@instructor_query_leading_space, $instructor_query_leading_space_expected,
                           'Removes preceding space before converting to tsquery in json_query');

my @instructor_prefix_wildcard_query = {'qtype' => 'instructor','contains' => 'contains','bool' => 'and','value' => 'd*'};
my $instructor_prefix_wildcard_query_expected = {"-and" => [
                                                    {"owning_lib"=> $orgs},
                                                    {"-not"=>{"+acmc"=>"is_archived"}},
                                                    {"id"=>{"in"=>{
                                                        "where"=>[
                                                            {"+acmr"=>"is_public"},
                                                            {"usr"=>{"in"=>
                                                                {"select"=>{"au"=>["id"]},
                                                                "where"=>{"name_kw_tsvector"=>
                                                                {"@@"=>{"value"=>["to_tsquery","d:*"]}}},
                                                            "from"=>"au"}}}],                                        
                                                        "select"=>{"acmcu"=>["course"]},
                                                        "from"=>{"acmcu" => "acmr"}}}}]};
is_query_parsed_correctly( \@instructor_prefix_wildcard_query, $instructor_prefix_wildcard_query_expected,
                           'Create a valid instructor prefix tsquery json query');



sub is_query_parsed_correctly {
    my ($query_hash, $expected, $description) = @_;
    my $ctx = {'processed_search_query' => '*'};
    my $query = OpenILS::WWW::EGCatLoader::_create_where_clause($ctx, $query_hash, $orgs);
    return is_deeply($query, $expected, $description);
}

1;
