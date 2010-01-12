#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Test::More 'no_plan';

use MARC::Record;
use OpenILS::Utils::MFHD;

my $testno = 0;

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

sub load_MARC_rec {
    my $fh = shift;
    my $rec;
    my $line;
    my $marc = undef;

    # skim to beginning of record (a non-blank, non comment line)
    while ($line = <$fh>) {
        chomp $line;
        last if (!($line =~ /^\s*$/) && !($line =~ /^#/));
    }

    return undef if !$line;

    $testno += 1;
    $marc = MARC::Record->new();
    carp('No record created!') unless $marc;

    $marc->leader('01119nas  2200313 a 4500');
    $marc->append_fields(
        MARC::Field->new('008', '970701c18439999enkwr p       0   a0eng  '));
    $marc->append_fields(
        MARC::Field->new('035', '', '', a => sprintf('%04d', $testno)));

    while ($line) {
        next if $line =~ /^#/;    # allow embedded comments

        return $marc if $line =~ /^\s*$/;

        my ($fieldno, $indicators, $rest) = split(/ /, $line, 3);
        my @inds = unpack('aa', $indicators);
        my $field;
        my @subfields;

        @subfields = ();
        foreach my $subfield (split(/\$/, $rest)) {
            next unless $subfield;

            my ($key, $val) = unpack('aa*', $subfield);
            push @subfields, $key, $val;
        }

        $field = MARC::Field->new(
            $fieldno, $inds[0], $inds[1],
            a => 'scratch',
            @subfields
        );

        $marc->append_fields($field);

        $line = <$fh>;
        chomp $line if $line;
    }
    return $marc;
}

my $rec;
my @captions;

open(my $testdata, "<mfhddata.txt") or die("Cannot open 'mfhddata.txt': $!");

while ($rec = load_MARC_rec($testdata)) {
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
            }
        }
    }
}

1;
