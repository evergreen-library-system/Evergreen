#!/usr/bin/perl
require 'oils_header.pl';
use strict; use warnings;
use OpenSRF::EX qw(:try);

# ------------------------------------------------------------
# Forks workers to force mods-ization of metarecords
# ------------------------------------------------------------

my $config	= shift; 
my $minid	= shift;
my $maxid	= shift;
my $workers	= shift || 1;
my $id		= 0;

die "$0 <config> <minid> <maxid> [<num_processes>]\n" unless $maxid;

die "too many workers..\n" if $workers > 20;

for(1..$workers) {
	last if fork();
	$id = $_;
}

osrf_connect($config);

for( $minid..$maxid ) {

	next unless $_ % $workers == $id;

	try {

		my $val = simplereq( 
			'open-ils.search', 
			'open-ils.search.biblio.metarecord.mods_slim.retrieve', 
			$_ );

		if( oils_is_event($val) ) {
			print "$_ - not found\n";
		} else {
			print "$_\n";
		}

	} catch Error with {
		print "$_ failed\n";
	};
}

