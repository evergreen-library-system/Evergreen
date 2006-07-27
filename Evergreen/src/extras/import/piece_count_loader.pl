#!/usr/bin/perl

use strict;
use warnings;

print <<SQL;
CREATE TABLE legacy_piece_count (barcode text, cnt int);
COPY legacy_piece_count (barcode, cnt) FROM STDIN;
SQL

while (<>) {
	chomp;
	my ($bc,$c) = split '\|';
	$bc =~ s/\s*$//o;
	print "$bc\t$c\n" if ($c > 1);
}

print '\.'."\n";
print "CREATE INDEX pc_bc_idx ON legacy_piece_count (barcode);\n";

