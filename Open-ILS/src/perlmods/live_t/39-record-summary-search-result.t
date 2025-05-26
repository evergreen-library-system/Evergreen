#!perl

use strict; use warnings;

use Test::More tests => 3;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenSRF::AppSession;

my $script = OpenILS::Utils::TestUtils->new;
$script->bootstrap;
our $apputils = "OpenILS::Application::AppUtils";

subtest 'single record' => sub {
    plan tests => 8;
    my $response = $apputils->simplereq(
    'open-ils.search',
    'open-ils.search.biblio.record.catalog_summary.staff',
    1,
    [248],
    {search_result => 1});

    my ($physical_description) = grep {$_->{label} eq 'Physical Description'} @{$response->{search_result}};
    is_deeply [sort @{ $physical_description->{value} }],
        ['374 p. ; 25 cm.', 'print'],
        'includes the physical description';
    
    is $physical_description->{display_as_link}, 'f', 'includes whether or not to display as a link';
    
    ok exists $physical_description->{character_limit},
        'includes the limit of characters to display in the search results view';

    ok exists $physical_description->{value_limit},
        'includes the limit of field values to display in the search results view';
    
    is $physical_description->{query_field}, 'keyword|physical_description',
        'includes a field that can be used to link to a search the relevant field for this term';

    is $physical_description->{content_type}, 'field',
        'includes the content_type in the search results view';

    my $upc = grep {$_->{label} eq 'UPC'} @{$response->{search_result}};
    is $upc, 0, 'does not include empty fields like UPC';

    my @labels = map {$_->{label}} @{$response->{search_result}};
    diag explain @labels;
    is_deeply \@labels,
        ['Physical Description', 'Edition', 'Origin Info', 'Publication Date', 'ISBN'],
        'entries are in the order specified by user';
};

subtest 'metarecord' => sub {
    plan tests => 1;
    my $response = $apputils->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.metabib.catalog_summary.staff',
        1,
        [241],
        {search_result => 1});

    my ($physical_description) = grep {$_->{label} eq 'Physical Description'} @{$response->{search_result}};
    is_deeply [sort @{$physical_description->{value}}],
        ['374 p. ; 25 cm.', 'print'],
        'includes the physical description';
};

subtest 'in non-English locale' => sub {
    plan tests => 2;

    my $e = new_editor(xact => 1);
    $e->init;
    my $session;
    my $i18n_l;
    my $translation;
    my $fake_locale = 'zz_ZZ';

    subtest 'setup' => sub {
        plan tests => 2;

        # Create a fake locale so we can test without messing up any other installed locale
        $i18n_l = Fieldmapper::config::i18n_locale->new;
        $i18n_l->name('Fake locale');
        $i18n_l->code('zz-ZZ');
        $i18n_l->marc_code('zzz');

        $translation = Fieldmapper::config::i18n_core->new;
        $translation->fq_field('cmf.label');
        $translation->identity_value(
            $e->search_config_metabib_field({name => 'physical_description'})->[0]->id
        );
        $translation->translation('zz-ZZ');
        $translation->string('Translated Physical Description 😸');

        $e->xact_begin;
        $e->create_config_i18n_locale($i18n_l);
        $e->create_config_i18n_core($translation);

        ok $translation->id, 'Created a fake translation';
        $e->commit;

        # Create a new session using our fake locale
        $session = OpenSRF::AppSession->create('open-ils.search', 1, 1, $fake_locale);
        is $session->session_locale, 'zz_ZZ', 'Session uses the new fake locale';
    };

    my $response = $session->request(
        'open-ils.search.biblio.record.catalog_summary.staff',
        1,
        [248],
        {search_result => 1}
    )->gather(1);

    my ($translated_physical_description) = grep {$_->{label} eq 'Translated Physical Description 😸'} @{$response->{search_result}};
    is_deeply [ sort @{ $translated_physical_description->{value} } ],
        ['374 p. ; 25 cm.', 'print'],
        'includes the translated label for the physical description';

    # Cleanup
    $e->xact_begin;
    $e->delete_config_i18n_locale($i18n_l);
    $e->delete_config_i18n_core($translation);
    $e->commit;
};
