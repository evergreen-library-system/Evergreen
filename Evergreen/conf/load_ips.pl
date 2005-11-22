#!/usr/bin/perl
use strict; use warnings;


# This file should be loaded by apache on startup (add to a "startup.pl" file)

open(F,"lib_ips.txt");

$OpenILS::WWW::Redirect::lib_ips_hash = {};
my $hash = $OpenILS::WWW::Redirect::lib_ips_hash;


while( my $data = <F> ) {

	chomp($data);

	my( $reglib, $ip1, $ip2 ) = split(/\t/, $data);
	next unless ($reglib and $ip1 and $ip2);

	my( $reg, $lib ) = split(/-/,$reglib);
	next unless ($reg and $lib);

#	print "$reg : $lib : $ip1 : $ip2\n";
	
	$hash->{$reg} = {} unless exists $hash->{$reg};
	$hash->{$reg}->{$lib} = [] unless exists $hash->{$reg}->{$lib};

	push( @{$hash->{$reg}->{$lib}}, [ $ip1, $ip2 ] );
}

