#!/usr/bin/perl
use strict;
use warnings;

use lib '/openils/lib/perl5/';

use OpenSRF::System;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::JSON;
use FileHandle;

use Time::HiRes qw/time/;
use Getopt::Long;

my @files;
my ($config, $output, @auto, @order, @wipe) =
	('/openils/conf/opensrf_core.xml', 'pg_loader-output');

GetOptions(
	'config=s'	=> \$config,
	'output=s'	=> \$output,
	'wipe=s'	=> \@wipe,
	'autoprimary=s'	=> \@auto,
	'order=s'	=> \@order,
);

my $pwd = `pwd`;
chop($pwd);

my %lineset;
my %fieldcache;

OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

my $main_out = FileHandle->new(">$output.sql") if ($output);

binmode($main_out,'utf8');

$main_out->print("SET CLIENT_ENCODING TO 'UNICODE';\n\n");
$main_out->print("BEGIN;\n\n");

my %out_files;
for my $h (@order) {
	$out_files{$h} = FileHandle->new(">$output.$h.sql");
	binmode($out_files{$h},'utf8');
}

my $count = 0;
my $starttime = time;
while ( my $rec = <> ) {
	next unless ($rec);

	my $row;
	try {
		$row = OpenSRF::Utils::JSON->JSON2perl($rec);
	} catch Error with {
		my $e = shift;
		warn "\n\n !!! Error : $e \n\n at or around line $count\n";
	};
	next unless ($row);

	my $class = $row->class_name;
	my $hint = $row->json_hint;

	next unless ( grep /$hint/, @order );

	if (!$fieldcache{$hint}) {
		my @cols = $row->real_fields;
		if (grep { $_ eq $hint} @auto) {
			@cols = grep { $_ ne $class->Identity } @cols;
		}

		$fieldcache{$hint} =
			{ table => $class->Table,
			  sequence => $class->Sequence,
			  pkey => $class->Identity,
			  fields => \@cols,
			};

        #XXX it burnnnsssessss
        $fieldcache{$hint}{table} =~ s/\.full_rec/.real_full_rec/o if ($hint eq 'mfr');

		my $fields = join(',', @{ $fieldcache{$hint}{fields} });
		$main_out->print( "DELETE FROM $fieldcache{$hint}{table};\n" ) if (grep {$_ eq $hint } @wipe);
		# Speed up loading of bib records
		if ($hint eq 'mfr') {
			$main_out->print("\nSELECT reporter.disable_materialized_simple_record_trigger();\n");
		}
		$main_out->print( "COPY $fieldcache{$hint}{table} ($fields) FROM '$pwd/$output.$hint.sql';\n" );

	}

	my $line = [map { $row->$_ } @{ $fieldcache{$hint}{fields} }];
	my @data;
	my $x = 0;
	for my $d (@$line) {
		if (!defined($d)) {
			$d = '\N';
		} else {
			$d =~ s/\f/\\f/gos;
			$d =~ s/\n/\\n/gos;
			$d =~ s/\r/\\r/gos;
			$d =~ s/\t/\\t/gos;
			$d =~ s/\\/\\\\/gos;
		}
		if ($hint eq 'bre' and $fieldcache{$hint}{fields}[$x] eq 'quality') {
			$d = int($d);
		}
		push @data, $d;
		$x++;
	}
	$out_files{$hint}->print( join("\t", @data)."\n" );

	if (!($count % 500)) {
		print STDERR "\r$count\t". $count / (time - $starttime);
	}

	$count++;
}

for my $hint (@order) {
    next if (grep { $_ eq $hint} @auto);
    next unless ($fieldcache{$hint}{sequence});
    $main_out->print("SELECT setval('$fieldcache{$hint}{sequence}'::TEXT, (SELECT MAX($fieldcache{$hint}{pkey}) FROM $fieldcache{$hint}{table}), TRUE);\n\n");
}

if (grep /^mfr$/, %out_files) {
	$main_out->print("SELECT reporter.enable_materialized_simple_record_trigger();\n");
}

$main_out->print("COMMIT;\n\n");
$main_out->close; 

