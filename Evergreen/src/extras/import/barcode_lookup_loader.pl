#!/usr/bin/perl

use Getopt::Long;

my ($usermap,$nonusers,$recirc) = ();

GetOptions(
        'usermap=s'        => \$usermap,
        'nonusers=s'        => \$nonusers,
        'recirc=s'        => \$recirc,
);

my %u_map;
open F, $usermap;
while (my $line = <F>) {
	chomp($line);
	my ($b,$i) = split(/\|/, $line);
	$b =~ s/^\s*(\S+)\s*$/$1/o;
	$i =~ s/^\s*(\S+)\s*$/$1/o;
	$u_map{$b} = $i;
}
close F;

print "CREATE TABLE legacy_baduser_map ( barcode text, id int, type text);\n";
print "COPY legacy_baduser_map FROM STDIN;\n";

open F, $nonusers;
while (<F>) {
	chomp;
	my ($p,$l,$b) = split '\|';
	next unless ($u_map{$b});
	print "$b\t$u_map{$b}\tN\n";
}
close F;

open F, $recirc;
while (<F>) {
	chomp;
	my ($b) = split '\|';
	next unless ($u_map{$b});
	print "$b\t$u_map{$b}\tR\n";
}
close F;

print "\\.\n";

