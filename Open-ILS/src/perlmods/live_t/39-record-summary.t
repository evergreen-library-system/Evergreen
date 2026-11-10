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

sub create_part {
    my ($label, $bib_record_id) = @_;
    my $part = Fieldmapper::biblio::monograph_part->new;
    $part->label($label);
    $part->record($bib_record_id);
    $part->creator(1);
    $part->editor(1);
    return $part;
}

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

# Create some monograph parts
my @parts = (create_part('Part 1', 248), create_part('Part 2', 248), create_part('Part 3', 245));

subtest('setup', sub {
    plan tests => 4;
    $e->xact_begin;
    $e->create_biblio_record_note($first_record_note);
    $e->create_biblio_record_note($second_record_note);
    $e->create_biblio_monograph_part($_) foreach @parts;
    $e->commit;

    my $notes = $e->search_biblio_record_note({record => 248});
    is(scalar(@{ $notes }), 1, 'Successfully added note to record 248');

    $notes = $e->search_biblio_record_note({record => 245});
    is(scalar(@{ $notes }), 1, 'Successfully added note to record 245');

    my $parts = $e->search_biblio_monograph_part({record => 248, deleted => 'f'});
    is(scalar(@{ $parts }), 2, 'Successfully added parts to record 248');

    $parts = $e->search_biblio_monograph_part({record => 245, deleted => 'f'});
    is(scalar(@{ $parts }), 1, 'Successfully added parts to record 245');
});

subtest('single record flavor', sub {
    plan tests => 3;

    my $org_unit = 4;
    my @record_ids = (248);
    my $response = $apputils->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.catalog_summary.staff',
        $org_unit,
        \@record_ids);
    is($response->{hold_count}, '0', 'includes the hold count');
    is($response->{record_note_count}, '1', 'includes the count of record notes');
    is($response->{monograph_part_count}, '2', 'includes the count of parts');
});

subtest('metarecord flavor', sub {
    plan tests => 6;

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
    is($response->{monograph_part_count}, '3', 'includes the sum count of parts on all individual records');
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
    my @library_group_counts = grep { $_->{library_group} && $_->{library_group} == 1000001 } @{$response->{copy_counts}};

    is($library_group_counts[0]->{available}, 4, 'includes the total items in the specified library group');
});

subtest('cleanup', sub {
    plan tests => 2;
    $e->xact_begin;
    $e->delete_biblio_record_note($first_record_note);
    $e->delete_biblio_record_note($second_record_note);
    $e->delete_biblio_monograph_part($_) foreach @parts;
    $e->commit;

    my $notes = $e->search_biblio_record_note({record => 248});
    is(scalar(@{ $notes }), 0, 'Successfully removed note from record');

    my $parts = $e->search_biblio_monograph_part({record => 248, deleted => 'f'});
    is(scalar(@{ $parts }), 0, 'Successfully removed monograph parts from record');
});
