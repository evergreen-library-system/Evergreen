#!/usr/bin/perl -w
use strict;
use Getopt::Long;

die "Obsolete ... records are ingested by stored procs within the db\n";

my ($start, $stop, $count, $group, $out, $method) = (1,1,1,50,'dynamic-reindex-script.sfsh', 'open-ils.ingest.full.biblio.record_list');
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
	push @list, $i;
	print SFSH "request open-ils.ingest $method [".join(',', @list)."]\n" if (@list);
	@list = ();
}
print SFSH "request open-ils.ingest $method [".join(',', @list)."]\n" if (@list);
