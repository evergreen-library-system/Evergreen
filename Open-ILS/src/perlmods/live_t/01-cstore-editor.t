#!perl

use strict; use warnings;
use Test::More tests => 1;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::TestUtils;

OpenILS::Utils::TestUtils->new->bootstrap;

subtest 'it has methods to count objects in the db', sub {
    plan tests => 2;

    my $editor = new_editor;
    $editor->init;

    my $record_count = $editor->count_biblio_record_entry({deleted => 'f'});
    ok $record_count > 10 && $record_count < 500_000,
        "It gets a reasonable count of biblio records: $record_count";

    $record_count = $editor->count_biblio_record_entry({id => -500});
    is $record_count, 0, 'It returns 0 if there are no matching objects';
}
