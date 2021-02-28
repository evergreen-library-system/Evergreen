#!perl

use Test::More tests => 3;

use strict; use warnings;

use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::TestUtils;


my $apputils = 'OpenILS::Application::AppUtils';
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;
my $e = new_editor();
$e->init;

diag('Testing multiclass search');

# SETUP: attach an item to a course at BR1
my $course_owning_org = 6;
my $other_org = 4;
my $course_id = 2;
my $bib_id = 223;

my @items = $apputils->simplereq(
    'open-ils.search',
    'open-ils.search.bib.copies.atomic',
     $bib_id, $course_owning_org, 1
);
my $item_id = $items[0][0]->{id};

my $acmcm = Fieldmapper::asset::course_module_course_materials->new;
$acmcm->course($course_id); # this course is housed at org 6 aka BR3
$acmcm->record($bib_id);
$acmcm->item($item_id);
$e->xact_begin;
$e->create_asset_course_module_course_materials( $acmcm ); # associated this bib and item with a course
$e->commit;

sub search_on_reserve_at {
    my ($desired_location) = @_;
    my $response = $apputils->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.multiclass.query',
        {}, # arghash
        "(keyword:dragons) on_reserve($desired_location)", # query string
        0 # Don't cache when we are in a test
    );
    return [map { $_->[0] } @{$response->{ids}}];
}

# Our tests!
is_deeply(search_on_reserve_at('all'), [$bib_id], 'on_reserve(all) search includes materials on reserve at any library');
is_deeply(search_on_reserve_at("$course_owning_org"), [$bib_id], 'on_reserve(6) search includes materials on reserve at ou 6 only');
is_deeply(search_on_reserve_at("$other_org"), [], 'on_reserve(4) search does not include materials on reserve at ou 6');


# Teardown: detach the item
my $no_longer_needed = $e->retrieve_asset_course_module_course_materials({item=>$item_id});
$e->xact_begin;
$e->delete_asset_course_module_course_materials($no_longer_needed);
$e->commit;