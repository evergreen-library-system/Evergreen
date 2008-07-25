#!/usr/bin/perl
use strict;

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
my ($config, $output, @auto, @order, @wipe, $quiet) =
	('/openils/conf/opensrf_core.xml');

GetOptions(
	'config=s'	=> \$config,
	'output=s'	=> \$output,
	'wipe=s'	=> \@wipe,
	'autoprimary=s'	=> \@auto,
	'order=s'	=> \@order,
	'quiet'		=> \$quiet,
);

my %lineset;
my %fieldcache;

OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

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

	if (!$lineset{$hint}) {
		$lineset{$hint} = [];
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
	}

	push @{ $lineset{$hint} }, [map { $row->$_ } @{ $fieldcache{$hint}{fields} }];

	if (!$quiet && !($count % 500)) {
		print STDERR "\r$count\t". $count / (time - $starttime);
	}

	$count++;
}

print STDERR "\nWriting file ...\n" if (!$quiet);

$output = '&STDOUT' unless ($output);
$output = FileHandle->new(">$output") if ($output);

binmode($output,'utf8');

$output->print("SET CLIENT_ENCODING TO 'UNICODE';\n\n");
$output->print("BEGIN;\n\n");

for my $h (@order) {
	# continue if there was no data for this table
	next unless ($fieldcache{$h});

	my $fields = join(',', @{ $fieldcache{$h}{fields} });
	$output->print( "DELETE FROM $fieldcache{$h}{table};\n" ) if (grep {$_ eq $h } @wipe);
	$output->print( "COPY $fieldcache{$h}{table} ($fields) FROM STDIN;\n" );

	for my $line (@{ $lineset{$h} }) {
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
			if ($h eq 'bre' and $fieldcache{$h}{fields}[$x] eq 'quality') {
				$d = int($d);
			}
			push @data, $d;
			$x++;
		}
		$output->print( join("\t", @data)."\n" );
	}

	$output->print('\.'."\n\n");
	
	$output->print("SELECT setval('$fieldcache{$h}{sequence}'::TEXT, (SELECT MAX($fieldcache{$h}{pkey}) FROM $fieldcache{$h}{table}), TRUE);\n\n")
		if (!grep { $_ eq $h} @auto);
}

$output->print("COMMIT;\n\n");
$output->close; 
