#!/usr/bin/perl -w

use strict;

my $entity_prefix = $ARGV[0];
my $filename = $ARGV[1];

if (! $entity_prefix && ! $filename) {
    print STDOUT "Usage:\n\tmake_entities.pl <prefix> <filename> > filename.new 2> entities.dtd\n\n\tmv filename.new filename\n\tsort entities.dtd | uniq >> lang.dtd\n\n";
    exit 0;
}

my %entity_hash = ();

open FILE, $filename;
while (my $line = <FILE>) {

    while ($line =~ /(accesskey|label|value)="(.+?)"/g) {
        my $attr = $1;
        my $value = $2; if ( $value =~ /^&.+;$/ ) { next; } # Already an entity
        my $entity = $value; $entity =~ s/\W/_/g; $entity = $entity_prefix . $entity . ( $attr eq "accesskey" ? ".accesskey" : ".label" );
        $line =~ s/$value/&$entity;/g;
        print STDERR qq^<!ENTITY $entity "$value">\n^;
    }
    print STDOUT $line;

}
close FILE;
