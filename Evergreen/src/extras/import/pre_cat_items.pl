#!/usr/bin/perl

use strict;
use warnings;

print <<SQL;
DROP TABLE legacy_pre_cat;
CREATE TABLE legacy_pre_cat (barcode text, lib text, title text, author text);
COPY legacy_pre_cat (barcode, lib, title, author) FROM STDIN;
SQL

while (<>) {
	chomp;
	my ($bc,$l,$t,$a) = split '\|';
	$bc =~ s/\s*$//o;
	print "$bc\t$l\t$t\t$a\n";
}

print '\.'."\n";
print "CREATE INDEX precat_bc_idx ON legacy_pre_cat (barcode);\n";

