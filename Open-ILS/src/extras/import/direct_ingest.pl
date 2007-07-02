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
use OpenSRF::Utils::JSON;
use Data::Dumper;
use FileHandle;

use Time::HiRes qw/time/;
use Getopt::Long;
use MARC::Batch;
use MARC::File::XML;
use MARC::Charset;

MARC::Charset->ignore_errors(1);

my ($auth, $config) =
	(0, '/openils/conf/opensrf_core.xml');

GetOptions(
	'config=s'	=> \$config,
	'authority'	=> \$auth,
);

my @ses;

open NEWERR,     ">&STDERR";

select NEWERR; $| = 1;
select STDERR; $| = 1;
select STDOUT; $| = 1;

OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

OpenILS::Application::Ingest->use;

my $meth = 'open-ils.ingest.full.biblio.object.readonly';
$meth = 'open-ils.ingest.full.authority.object.readonly' if ($auth);

$meth = OpenILS::Application::Ingest->method_lookup( $meth );

my $count = 0;
my $starttime = time;
while (my $rec = <>) {
	next unless ($rec);

	my $bib = OpenSRF::Utils::JSON->JSON2perl($rec);
	my $data;

	try {
		($data) = $meth->run( $bib );
	} catch Error with {
		my $e = shift;
		warn "Couldn't process record: $e\n >>> $rec\n";
	};

	next unless $data;

	postprocess( { bib => $bib, worm_data => $data } );

	if (!($count % 20)) {
		print NEWERR "\r$count\t". $count / (time - $starttime);
	}

	$count++;
}

sub postprocess {
	my $data = shift;

	my $bib = $data->{bib};
	my $full_rec = $data->{worm_data}->{full_rec};

	my $field_entries = $data->{worm_data}->{field_entries} unless ($auth);
	my $fp = $data->{worm_data}->{fingerprint} unless ($auth);
	my $rd = $data->{worm_data}->{descriptor} unless ($auth);

	$bib->fingerprint( $fp->{fingerprint} ) unless ($auth);
	$bib->quality( $fp->{quality} ) unless ($auth);

	print( OpenSRF::Utils::JSON->perl2JSON($bib)."\n" );
	unless ($auth) {
		print( OpenSRF::Utils::JSON->perl2JSON($rd)."\n" );
		print( OpenSRF::Utils::JSON->perl2JSON($_)."\n" ) for (@$field_entries);
	}

	print( OpenSRF::Utils::JSON->perl2JSON($_)."\n" ) for (@$full_rec);
}

