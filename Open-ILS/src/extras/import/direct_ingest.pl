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

my ($max_uri, $max_cn, $auth, $config, $quiet) =
	(0, 0, 0, '/openils/conf/opensrf_core.xml');

GetOptions(
	'config=s'	=> \$config,
	'authority'	=> \$auth,
	'quiet'		=> \$quiet,
	'max_uri=i'	=> \$max_uri,	
	'max_cn=i'	=> \$max_cn,	
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
		($data) = $meth->run( $bib => $max_cn => $max_uri );
	} catch Error with {
		my $e = shift;
		warn "Couldn't process record: $e\n >>> $rec\n";
	};

	next unless $data;

	postprocess( { bib => $bib, ingest_data => $data } );

	if (!$quiet && !($count % 20)) {
		print NEWERR "\r$count\t". $count / (time - $starttime);
	}

	$count++;
}

sub postprocess {
	my $data = shift;

	my $bib = $data->{bib};
	my $full_rec = $data->{ingest_data}->{full_rec};

	my $field_entries = $data->{ingest_data}->{field_entries} unless ($auth);
	my $fp = $data->{ingest_data}->{fingerprint} unless ($auth);
	my $rd = $data->{ingest_data}->{descriptor} unless ($auth);
	my $uri = $data->{ingest_data}->{uri} unless ($auth);

	$bib->fingerprint( $fp->{fingerprint} ) unless ($auth);
	$bib->quality( $fp->{quality} ) unless ($auth);

	print( OpenSRF::Utils::JSON->perl2JSON($bib)."\n" );
	unless ($auth) {
		print( OpenSRF::Utils::JSON->perl2JSON($rd)."\n" );
		print( OpenSRF::Utils::JSON->perl2JSON($_)."\n" ) for (@$field_entries);
		for my $u (@$uri) {
			print( OpenSRF::Utils::JSON->perl2JSON($u->{call_number})."\n" ) if $u->{call_number}->isnew;
			print( OpenSRF::Utils::JSON->perl2JSON($u->{uri})."\n" ) if $u->{uri}->isnew;

			my $umap = Fieldmapper::asset::uri_call_number_map->new;
			$umap->uri($u->{uri}->id);
			$umap->call_number($u->{call_number}->id);
			print( OpenSRF::Utils::JSON->perl2JSON($umap)."\n" );

			$max_cn = $u->{call_number}->id + 1 if $u->{call_number}->isnew;
			$max_uri = $u->{uri}->id + 1 if $u->{uri}->isnew;
		}
	}

	print( OpenSRF::Utils::JSON->perl2JSON($_)."\n" ) for (@$full_rec);
}

