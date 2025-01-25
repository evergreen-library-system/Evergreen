#!perl

use strict; use warnings;

use Test::More tests => 5;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

diag('Test the open-ils.search.biblio.record.catalog_summary family of methods');

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;
our $apputils = "OpenILS::Application::AppUtils";
my $e = new_editor;
$e->init;

use constant WORKSTATION_NAME => 'BR4-test-39-record-summary.t';

# Create two new record notes
my $first_record_note = Fieldmapper::biblio::record_note->new;
$first_record_note->record(248);
$first_record_note->value('this is my favorite record!');
$first_record_note->creator(1);
$first_record_note->editor(1);

my $second_record_note = Fieldmapper::biblio::record_note->new;
$second_record_note->record(245);
$second_record_note->value('this is my second favorite record!');
$second_record_note->creator(1);
$second_record_note->editor(1);

subtest('setup', sub {
    plan tests => 2;
    $e->xact_begin;
    $e->create_biblio_record_note($first_record_note);
    $e->create_biblio_record_note($second_record_note);
    $e->commit;

    my $notes = $e->search_biblio_record_note({record => 248});
    is(scalar(@{ $notes }), 1, 'Successfully added note to record 248');

    $notes = $e->search_biblio_record_note({record => 245});
    is(scalar(@{ $notes }), 1, 'Successfully added note to record 245');
});

subtest('single record flavor', sub {
    plan tests => 2;

    my $org_unit = 4;
    my @record_ids = (248);
    my $response = $apputils->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.catalog_summary.staff',
        $org_unit,
        \@record_ids);
    is($response->{hold_count}, '0', 'includes the hold count');
    is($response->{record_note_count}, '1', 'includes the count of record notes');
});

subtest('metarecord flavor', sub {
    plan tests => 5;

    my $org_unit = 4;
    my $metabib = $e->search_metabib_metarecord({master_record => 248});

    my @metarecord_ids = ($metabib->[0]->id);
    my $response = $apputils->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.metabib.catalog_summary.staff',
        $org_unit,
        \@metarecord_ids);
    is($response->{hold_count}, '0', 'includes the hold count');
    is($response->{metabib_id}, $metabib->[0]->id, 'includes the metabib id');
    is($response->{id}, 248, 'includes the bib id');

    my @expected_metabib_records = (245, 246, 247, 248);
    is_deeply($response->{metabib_records}, \@expected_metabib_records,
        'includes a list of bib records in the metarecord');
    is($response->{record_note_count}, '2', 'includes the sum count of notes on all individual records');
});

subtest('with location_group option', sub {
    plan tests => 1;

    my $org_unit = 4;
    my @record_ids = (248);
    my $response = $apputils->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.catalog_summary.staff',
        $org_unit,
        \@record_ids,
        {library_group => 1000001});
    my @library_group_counts = grep { $_->{lasso} == 1000001 } @{$response->{copy_counts}};

    is($library_group_counts[0]->{available}, 4, 'includes the total items in the specified library group');
});

subtest('cleanup', sub {
    plan tests => 1;
    $e->xact_begin;
    $e->delete_biblio_record_note($first_record_note);
    $e->delete_biblio_record_note($second_record_note);
    $e->commit;

    my $notes = $e->search_biblio_record_note({record => 248});
    is(scalar(@{ $notes }), 0, 'Successfully removed note from record');
});
