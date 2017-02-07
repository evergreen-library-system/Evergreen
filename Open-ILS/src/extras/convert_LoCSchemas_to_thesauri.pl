#!/usr/bin/perl
use warnings;
use strict;
use JSON;


# Pulled original data from LoC on Feb 7, 2017.
# URL: http://id.loc.gov/vocabulary/subjectSchemes.json
# URL: http://id.loc.gov/vocabulary/genreFormSchemes.json
# Post-processing with iconv to convert from Latin1 to UTF8
# See files: subjectSchemes.utf8.json, genreFormSchemes.utf8.json

binmode(STDOUT, ":utf8");

local $/ = undef;
my $json = decode_json(<>);

for my $node (@$json) {
    next unless $node->{'@type'}[2] and $node->{'@type'}[2] eq 'http://www.w3.org/2004/02/skos/core#Concept';

    my $id = $node->{'@id'};
    my $code = $node->{'http://www.loc.gov/mads/rdf/v1#code'}[0]{'@value'};

    my $en_label;
    my %per_labels;

    for my $label_type ( qw|
            http://www.w3.org/2000/01/rdf-schema#label
            http://www.loc.gov/mads/rdf/v1#authoritativeLabel
            http://www.w3.org/2004/02/skos/core#prefLabel
    | ) {
        for my $plabel (@{$node->{$label_type}}) {
            my $lang = $plabel->{'@language'};
            my $value= $plabel->{'@value'};
            if ($lang eq 'en') {
                $en_label = $value;
                next;
            }
            $value =~ s/"/'/g;
            $per_labels{$lang} = $value;
        }
    }

    ($en_label) = values(%per_labels) if (!$en_label and keys(%per_labels) == 1);

    next unless $en_label;

    print "$code\t$id\t$en_label\t".join(',', map {"\"$_\"=>\"$per_labels{$_}\""} keys %per_labels)."\n";
}


