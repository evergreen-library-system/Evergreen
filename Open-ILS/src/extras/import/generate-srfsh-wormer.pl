#!/usr/bin/perl -w
use strict;
use Getopt::Long;

my ($start, $stop, $count, $group, $out, $method) = (1,1,1,50,'dynamic-wormizer-script.sfsh', 'open-ils.worm.wormize.biblio.nomap.noscrub');
GetOptions (	"start=i" => \$start,
		"end=i"   => \$stop,
		"groupsize=i"   => \$group,
		"count=i"   => \$count,
		"output=s"   => \$out,
		"method=s" => \$method,
);

$stop = $start + $count unless ($stop);

open SFSH, ">$out" or die("Can't open $out!  $!");

my @list;
for my $i ( $start .. $stop ) {
	if ( $i % $group ) {
		push @list, $i;
		next;
	}
	print SFSH "request open-ils.storage $method [".join(',', @list)."]\n" if (@list);
	@list = ($i);
}
print SFSH "request open-ils.storage $method [".join(',', @list)."]\n" if (@list);
