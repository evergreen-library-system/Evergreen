#!/usr/bin/perl
use strict;

use lib '/openils/lib/perl5/';

use OpenSRF::System;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use JSON;
use FileHandle;

use Time::HiRes qw/time/;
use Getopt::Long;

my @files;
my ($config, $output, @auto, @order) =
	('/openils/conf/bootstrap.conf');

GetOptions(
	'config=s'	=> \$config,
	'output=s'	=> \$output,
	'autoprimary=s'	=> \@auto,
	'order=s'	=> \@order,
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
		$row = JSON->JSON2perl($rec);
	} catch Error with {
		my $e = shift;
		warn "\n\n !!! Error : $e \n\n at or around line $count\n";
	};
	die unless ($row);

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
			  fields => \@cols,
			};
	}

	push @{ $lineset{$hint} }, [map { $row->$_ } @{ $fieldcache{$hint}{fields} }];

	if (!($count % 500)) {
		print STDERR "\r$count\t". $count / (time - $starttime);
	}

	$count++;
}

print STDERR "\nWriting file ...\n";

$output = '&STDOUT' unless ($output);
$output = FileHandle->new(">$output") if ($output);

binmode($output,'utf8');

$output->print("SET CLIENT_ENCODING TO 'UNICODE';\n\n");

for my $h (@order) {
	my $fields = join(',', @{ $fieldcache{$h}{fields} });
	$output->print( "COPY $fieldcache{$h}{table} ($fields) FROM STDIN;\n" );

	for my $line (@{ $lineset{$h} }) {
		my @data;
		for my $d (@$line) {
			if (!defined($d)) {
				$d = '\N';
			} else {
				$d =~ s/\t/\\t/go;
				$d =~ s/\\/\\\\/go;
			}
			push @data, $d;
		}
		$output->print( join("\t", @data)."\n" );
	}

	$output->print('\.'."\n\n");
}
