#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Test::More 'no_plan';
use File::Basename qw(dirname);

use MARC::Record;
use OpenILS::Utils::MFHD;

use testlib;

my $testno = 1;

sub right_answer {
    my $holding = shift;
    my $answer  = {};

    foreach my $subfield (split(/\|/, $holding->subfield('x'))) {
        next unless $subfield;

        my ($key, $val) = unpack('aa*', $subfield);
        $answer->{$key} = $val;
    }

    return $answer;
}


my $rec;
my @captions;

my $testfile = dirname(__FILE__) . "/mfhddata.txt";
open(my $testdata, "<", $testfile) or die("Cannot open '$testfile': $!");

while ($rec = testlib::load_MARC_rec($testdata, $testno++)) {
    $rec = MFHD->new($rec);

    foreach my $cap (sort { $a->tag <=> $b->tag } $rec->field('85.')) {
        my $htag;
        my @holdings;

        ($htag = $cap->tag) =~ s/^85/86/;
        @holdings = $rec->holdings($htag, $cap->subfield('8'));

        if (!ok(scalar @holdings, "holdings defined " . $cap->subfield('8'))) {
            next;
        }

        foreach my $field (@holdings) {
          TODO: {
                local $TODO = "unimplemented"
                  if ($field->subfield('z') =~ /^TODO/);
                is_deeply($field->next, right_answer($field),
                    $field->subfield('8') . ': ' . $field->subfield('z'));

                if ($field->subfield('y')) {
                    is($field->chron_to_date(), $field->subfield('y'), 'Chron-to-date test');
                }
            }
        }
    }
}

close $testdata;

# test: passthru_open_ended
my $testfile2 = dirname(__FILE__) . "/mfhddata2.txt";
open($testdata, "<", $testfile2) or die("Cannot open '$testfile2': $!");

$rec = MFHD->new(testlib::load_MARC_rec($testdata, $testno));
my $rec2 = MFHD->new(testlib::load_MARC_rec($testdata, $testno));

my @holdings_a = $rec->get_decompressed_holdings(($rec->captions('853'))[0], {'passthru_open_ended' => 1});
my @holdings_b = $rec2->holdings_by_caption(($rec2->captions('853'))[0]);

is_deeply(\@holdings_a, \@holdings_b, 'passthru open ended');

# test: compressed to last
$testno++;

$rec = MFHD->new(testlib::load_MARC_rec($testdata, $testno));
$rec2 = MFHD->new(testlib::load_MARC_rec($testdata, $testno));

@holdings_a = $rec->holdings_by_caption(($rec->captions('853'))[0]);
@holdings_b = $rec2->holdings_by_caption(($rec2->captions('853'))[0]);

is_deeply($holdings_a[0]->compressed_to_last, $holdings_b[0], 'compressed to last, normal');
is($holdings_a[1]->compressed_to_last, undef, 'compressed to last, open ended');

# test: get compressed holdings
$testno++;

$rec = MFHD->new(testlib::load_MARC_rec($testdata, $testno));
$rec2 = MFHD->new(testlib::load_MARC_rec($testdata, $testno));

@holdings_a = $rec->get_compressed_holdings(($rec->captions('853'))[0]);
@holdings_b = $rec2->holdings_by_caption(($rec2->captions('853'))[0]);

is_deeply(\@holdings_a, \@holdings_b, 'get compressed holdings');


# test: get compressed holdings, open ended member
$testno++;

$rec = MFHD->new(testlib::load_MARC_rec($testdata, $testno));
$rec2 = MFHD->new(testlib::load_MARC_rec($testdata, $testno));

@holdings_a = $rec->get_compressed_holdings(($rec->captions('853'))[0]);
@holdings_b = $rec2->holdings_by_caption(($rec2->captions('853'))[0]);

is_deeply(\@holdings_a, \@holdings_b, 'get compressed holdings, open ended member');

# test comparisons, for all operands, for all types of holdings
$testno++;

$rec = MFHD->new(testlib::load_MARC_rec($testdata, $testno));
$rec2 = MFHD->new(testlib::load_MARC_rec($testdata, $testno));

@holdings_a = $rec->holdings_by_caption(($rec->captions('853'))[0]);
@holdings_b = $rec2->holdings_by_caption(($rec2->captions('853'))[0]);

unshift(@holdings_a, "zzz I am NOT a holding");
push(@holdings_b, "zzz I am NOT a holding");

push(@holdings_a, undef);
unshift(@holdings_b, undef);

@holdings_a = sort { $a cmp $b } @holdings_a;
my $seqno = 1;
foreach my $holding (@holdings_a) {
    if (ref $holding) {
        $holding->seqno($seqno);
        $seqno++;
    }
}

is_deeply(\@holdings_a, \@holdings_b, 'comparison testing via sort');

# test: get combined holdings
$testno++;

$rec = MFHD->new(testlib::load_MARC_rec($testdata, $testno));
$rec2 = MFHD->new(testlib::load_MARC_rec($testdata, $testno));

@holdings_a = $rec->get_combined_holdings(($rec->captions('853'))[0]);
@holdings_b = $rec2->holdings_by_caption(($rec2->captions('853'))[0]);

is_deeply(\@holdings_a, \@holdings_b, 'get combined holdings');


close $testdata;
1;
