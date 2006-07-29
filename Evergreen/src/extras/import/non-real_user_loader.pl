#!/usr/bin/perl

use strict;
use warnings;

print <<SQL;
CREATE TABLE legacy_non_real_user (profile text, lib text, barcode text);
COPY legacy_non_real_user (profile, lib, barcode) FROM STDIN;
SQL

while (<>) {
	chomp;
	my ($p,$l,$b) = split '\|';
	print "$p\t$l\t$b\n";
}

print '\.'."\n";

