#!/usr/bin/perl

print "CREATE TABLE legacy_renewal_count ( barcode text, cnt int);\n";
print "COPY legacy_renewal_count FROM STDIN;\n";

while (<>) {
	chomp;
	my ($b,$c) = split '\|';
	$b =~ s/\s*$//o;
	print "$b\t$c\n";
}

print "\\.\n";

