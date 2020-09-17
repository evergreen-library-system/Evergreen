#!perl
 
use strict; use warnings;
use Test::More tests => 5;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;

diag("Test the course materials module.");

my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';

# we need auth to access protected APIs
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});

my $authtoken = $script->authtoken;
ok($authtoken, 'Have an authtoken');

my $e = new_editor(xact => 1);
$e->init;


# -----------------------------------------------------------------------------
# 1. Let's attach an existing biblio record entry to course #1, then delete it
# -----------------------------------------------------------------------------

my $acmcm = Fieldmapper::asset::course_module_course_materials->new;
$acmcm->course(1);
$acmcm->id(9999);
$acmcm->record(55);
$acmcm->temporary_record(0);
$e->create_asset_course_module_course_materials( $acmcm ); # associated this bib record with a course
$e->commit;

$apputils->simplereq('open-ils.courses', 'open-ils.courses.detach_material', $authtoken, 9999);

my $results = $e->search_asset_course_module_course_materials({id => 9999});
is(scalar(@$results), 0, 'Successfully deleted acmcm');

$results = $e->search_biblio_record_entry({id => 55, deleted => 0});

is(scalar(@$results), 1,
    'Did not inadvertantly delete bre');


# -----------------------------------------------------------------------------
# 2. Let's create a brief temporary bib record, attach it to course #1, then detach it
# -----------------------------------------------------------------------------

my $temp_tcn_source = 'temporary bib record for course materials module test';

$e->xact_begin;
my $bre = Fieldmapper::biblio::record_entry->new;
$bre->marc('<record></record>');
$bre->tcn_source($temp_tcn_source); #Use the tcn_source field, since Cstore rewrites the last_xact_id field
my $temp_bib = $e->create_biblio_record_entry($bre) or die $e->die_event;
$e->commit;

$e->xact_begin;
$acmcm = Fieldmapper::asset::course_module_course_materials->new;
$acmcm->course(1);
$acmcm->id(9998);
$acmcm->record($temp_bib->id);
$acmcm->temporary_record(1); # this one is temporary, like brief records created in the course module interface
$e->create_asset_course_module_course_materials( $acmcm ); # associated this bib record with a course
$e->commit;

$apputils->simplereq('open-ils.courses', 'open-ils.courses.detach_material', $authtoken, 9998);

sleep 1;

$results = $e->search_asset_course_module_course_materials({id => 9998});
is(scalar(@$results), 0, 'Successfully deleted acmcm');

$results = $e->search_biblio_record_entry({tcn_source=>$temp_tcn_source,deleted=>0});
is(scalar(@$results), 0, 'Successfully deleted bre');


