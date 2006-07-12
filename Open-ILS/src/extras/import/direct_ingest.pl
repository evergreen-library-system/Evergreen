#!/usr/bin/perl
use strict;
use warnings;

use lib '/openils/lib/perl5/';

use OpenSRF::System;
use OpenSRF::EX qw/:try/;
use OpenSRF::AppSession;
use OpenSRF::Application;
use OpenSRF::MultiSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::Ingest;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;
use JSON;
use Data::Dumper;
use FileHandle;

use Time::HiRes qw/time/;
use Getopt::Long;
use MARC::Batch;
use MARC::File::XML;
use MARC::Charset;

MARC::Charset->ignore_errors(1);

my ($workers, $config, $prefix) =
	(1, '/openils/conf/bootstrap.conf', 'marc-out-');

GetOptions(
	'threads=i'	=> \$workers,
	'config=s'	=> \$config,
	'prefix=s'	=> \$prefix,
);

my @ses;

open NEWERR,     ">&STDERR";

select NEWERR; $| = 1;
select STDERR; $| = 1;
select STDOUT; $| = 1;

for (1 .. $workers) {
	my ($r,$w);
	pipe($r,$w);
	if (fork) {
		push @ses, $w;
	} else {
		$0 = "Local Ingest Worker $_";
		worker($r, $_);
		exit;
	}
}
$0 = "Local Ingest Master";

sub worker {
	my $pipe = shift;
	my $file = shift;

	OpenSRF::System->bootstrap_client( config_file => $config );
	Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

	OpenILS::Application::Ingest->use;

	my $f = new FileHandle(">${prefix}$file");
	while (my $rec = <$pipe>) {

		my $bib = JSON->JSON2perl($rec);
		my $data;

		try {
			($data) = OpenILS::Application::Ingest
				->method_lookup( 'open-ils.ingest.full.biblio.object.readonly' )
				->run( $bib );
		} catch Error with {
			my $e = shift;
			warn "Couldn't process record: $e\n >>> $rec\n";
		};

		next unless $data;

		postprocess(
			{ bib		=> $bib,
		  	worm_data	=> $data,
			},
			$f
		);
	}
}

my $count = 0;
my $starttime = time;
while ( my $rec = <> ) {
	next unless ($rec);
	my $session_index = $count % $workers;

	$ses[$session_index]->printflush( $rec );

	if (!($count % 20)) {
		print NEWERR "\r$count\t". $count / (time - $starttime);
	}

	$count++;
}

sub postprocess {
	my $data = shift;
	my $f = shift;

	my $bib = $data->{bib};
	my $field_entries = $data->{worm_data}->{field_entries};
	my $full_rec = $data->{worm_data}->{full_rec};
	my $fp = $data->{worm_data}->{fingerprint};
	my $rd = $data->{worm_data}->{descriptor};

	$bib->fingerprint( $fp->{fingerprint} );
	$bib->quality( $fp->{quality} );

	$f->printflush( JSON->perl2JSON($bib)."\n" );
	$f->printflush( JSON->perl2JSON($rd)."\n" );
	$f->printflush( JSON->perl2JSON($_)."\n" ) for (@$field_entries);
	$f->printflush( JSON->perl2JSON($_)."\n" ) for (@$full_rec);
}

