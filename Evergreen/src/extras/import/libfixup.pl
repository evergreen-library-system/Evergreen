#!/usr/bin/perl

use strict;

my $new = shift;
my $old = shift;

open N, $new;
open O, $old;

my %oldlibs;
while (<O>) {
	chomp;
	my ($sname, $lib, $sys) = split /\t/;
	my ($sys_prefix) = split /-/;

	$oldlibs{$sys_prefix} = $sys;
}

while (<N>) {
	chomp;
	my ($sname,$lib) = split /\|/;
	my ($sys_prefix) = split /-/, $sname;
	$lib =~ s/^[^-]+-(.+)/$1/o;
	print "$sname\t$lib\t$oldlibs{$sys_prefix}\n";
}
