#!/usr/bin/perl

use strict;
use warnings;

print <<SQL;
CREATE TABLE legacy_recirc_lib (barcode text, lib text);
COPY legacy_recirc_lib (barcode, lib) FROM STDIN;
SQL

while (<>) {
	chomp;
	my ($b,$l) = split '\|';
	print "$b\t$l\n";
}

print '\.'."\n";

