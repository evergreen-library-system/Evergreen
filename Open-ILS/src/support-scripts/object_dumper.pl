#!/usr/bin/perl
# ---------------------------------------------------------------------
# Generic databse object dumper.
# ./object_dumper.pl <bootstrap_config> <type>, <type>, ...
# ./object_dumper.pl /openils/conf/opensrf_core.xml permission.grp_tree
# ---------------------------------------------------------------------

use strict; 
use warnings;
use OpenSRF::Utils::JSON;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;

my $config = shift || die "bootstrap config required\n";

OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import;

require OpenILS::Utils::CStoreEditor;
my $e = OpenILS::Utils::CStoreEditor->new;

for my $t (@ARGV) {
	$t =~ s/\./_/og;
	my $m = "retrieve_all_$t";
	my $d = $e->$m();
	print OpenSRF::Utils::JSON->perl2JSON($_) . "\n" for @$d;
}
