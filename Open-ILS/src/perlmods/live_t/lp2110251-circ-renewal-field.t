#!perl
use strict; use warnings;
use Test::More tests => 5;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);
use OpenILS::Utils::Fieldmapper;
use Data::Dumper;

my $script = OpenILS::Utils::TestUtils->new();

$script->bootstrap();

diag('LP2110251 Verify Circ Renewal Field');

my $circ = Fieldmapper::action::circulation->new;

# Check that the renewal field exists.
ok($circ->has_field('renewal'), 'circ object has renewal field');

# Check that it is a link
is($circ->FieldDatatype('renewal'), 'link', 'circ renewal field is a link');
SKIP: {
    # Check link properties if Fieldmapper supports it, 3.15+
    eval {
        my $link = $circ->FieldLink('renewal');
        is($link->{class}, 'circ', 'renwal links to circ');
        is($link->{key}, 'parent_circ', 'renewal key field is parent_circ');
        is($link->{reltype}, 'might_have', 'renewal is a "might_have" link');
    };
    if ($@) {
        skip 'test not supported by your Fieldmapper', 3;
    }
};
