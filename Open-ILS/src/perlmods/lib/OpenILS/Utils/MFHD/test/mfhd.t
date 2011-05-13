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

1;
