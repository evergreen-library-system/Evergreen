#!perl

use strict; use warnings;
use Test::More tests => 8;
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


# --------------------------------------------------------------------------
# 3. Let's attach an existing item record entry to course #1, then detach it
# --------------------------------------------------------------------------

# Create an item with temporary location and library, so that we can confirm its fields revert on course material detach
my $acp = Fieldmapper::asset::copy->new;
my $item_id = int (rand (1_000_000) );
my $acmcm_id = int (rand (1_000_000) );
$acp->deleted(0);
$acp->call_number(1);
$acp->creator(1);
$acp->editor(1);
$acp->circ_lib(6);          # temporary value
$acp->age_protect(1);
$acp->barcode( $bre->id . '-1' );
$acp->create_date('now');
$acp->edit_date('now');
$acp->active_date('now');
$acp->status_changed_time('now');
$acp->status(0);
$acp->location(136);        # temporary value
$acp->loan_duration(2);
$acp->fine_level(2);
$acp->deposit(0);
$acp->deposit_amount(0.00);
$acp->ref(0);
$acp->holdable(1);
$acp->opac_visible(1);
$acp->mint_condition(1);
$acp->id($item_id);
$e->xact_begin;
$e->create_asset_copy( $acp );
$e->commit;

$acmcm = Fieldmapper::asset::course_module_course_materials->new;

$acmcm->course(1);
$acmcm->id($acmcm_id);
$acmcm->record(55);
$acmcm->item($item_id);
$acmcm->original_status(0);
$acmcm->original_location(1);
$acmcm->original_circ_lib(5);
$acmcm->temporary_record(0);
$e->xact_begin;
$e->create_asset_course_module_course_materials( $acmcm ); # associated this bib record with a course
$e->commit;

$apputils->simplereq('open-ils.courses', 'open-ils.courses.detach_material', $authtoken, $acmcm_id);

$results = $e->search_asset_course_module_course_materials({id => $acmcm_id});
is(scalar(@$results), 0, 'Successfully deleted acmcm');

# Re-load the acp into memory from the db
$acp = $e->retrieve_asset_copy($item_id);
is($acp->location, 1, "Successfully reverted item's shelving location");
is($acp->circ_lib, 5, "Successfully reverted item's circ_lib");