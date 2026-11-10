#!perl

use strict; use warnings;

use Test::More tests => 2;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenSRF::AppSession;

my $script = OpenILS::Utils::TestUtils->new;
$script->bootstrap;
my $apputils = "OpenILS::Application::AppUtils";

subtest 'single record' => sub {
    plan tests => 7;
    my $response = $apputils->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.catalog_summary.staff',
        1,
        [248],
        {staff_view => 1}
    );

    my ($physical_description) = grep {$_->{label} && $_->{label} eq 'Physical Description'} @{$response->{staff_view}->[0]};
    is_deeply $physical_description->{value},
        ['374 p. ; 25 cm.', 'print'],
        'includes the physical description';

    is $physical_description->{display_as_link}, 'f', 'includes whether or not to display as a link';

    
    ok exists $physical_description->{character_limit},
        'includes the limit of characters to display in the search results view';

    is $physical_description->{query_field}, 'keyword|physical_description',
        'includes a field that can be used to link to a search the relevant field for this term';

    my ($subjects) = grep {$_->{label} && $_->{label} eq 'All Subjects'} @{$response->{staff_view}->[2]};
    is_deeply $subjects->{value},
        ['Puzzles -- Fiction', 'Utopias -- Fiction', 'Virtual reality -- Fiction', 'Regression (Civilization) -- Fiction'],
        'includes subjects';

    my @first_column_fields = grep {$_->{content_type} eq 'field'} @{$response->{staff_view}->[0]};
    my @first_column_labels = map {$_->{label}} @first_column_fields;
    is_deeply \@first_column_labels,
        ['Title Proper', 'Author', 'Edition', 'Origin Info', 'Type of Resource',
        'Physical Description', 'ISBN'],
        'entries are in the order specified by user';

    my @third_column_types = map {$_->{content_type}} @{$response->{staff_view}->[2]};
    is_deeply \@third_column_types,
        ['item_counts', 'hold_counts', 'field', 'field', 'formats_and_editions'],
        'entries include their content_type';
};

subtest 'metarecord' => sub {
    plan tests => 1;
    my $response = $apputils->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.metabib.catalog_summary.staff',
        1,
        [241],
        {staff_view => 1});

    my ($physical_description) = grep {$_->{label} eq 'Physical Description'} @{$response->{staff_view}->[0]};
    is_deeply $physical_description->{value},
        ['374 p. ; 25 cm.', 'print'],
        'includes the physical description';
};
