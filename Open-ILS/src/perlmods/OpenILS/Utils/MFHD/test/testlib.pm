package testlib;

use strict;
use warnings;

use base 'Exporter';

our @EXPORT_OK = qw(load_MARC_rec);

use Data::Dumper;

use MARC::Record;

sub load_MARC_rec {
    my $fh = shift;
    my $testno = shift;
    my $rec;
    my $line;
    my $marc = undef;

    # skim to beginning of record (a non-blank, non comment line)
    while ($line = <$fh>) {
        chomp $line;
        last if (!($line =~ /^\s*$/) && !($line =~ /^#/));
    }

    return undef if !$line;

    $marc = MARC::Record->new();
    carp('No record created!') unless $marc;

    $marc->leader('01119nas  22003134a 4500');
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
            @subfields
        );

        $marc->append_fields($field);

        $line = <$fh>;
        chomp $line if $line;
    }
    return $marc;
}

1;
