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
use OpenILS::Application::Storage;
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

my @files;
my ($type, $config, $autoprimary) =
	('biblio.record_entry', '/openils/conf/bootstrap.conf', 0);

GetOptions(
	'type=s'	=> \$type,
	'config=s'	=> \$config,
	'autoprimary'	=> \$config,
);


OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

OpenILS::Application::Storage->use;
OpenILS::Application::Storage->initialize;
OpenILS::Application::Storage->child_init || die;

if ($autoprimary) {
	OpenILS::Application::Storage->autoprimary(1);
}

my $base = "open-ils.storage.direct.$type.batch.create";

OpenSRF::Application->method_lookup( "$base.start" )->run; 

my $count = 0;
my $starttime = time;
while ( my $rec = <> ) {
	next unless ($rec);

	my $row = JSON->JSON2perl($rec);

	OpenSRF::Application->method_lookup( "$base.push" )->run($row); 


	if (!($count % 20)) {
		print STDERR "\r$count\t". $count / (time - $starttime);
	}

	$count++;
}
OpenSRF::Application->method_lookup( "$base.finish" )->run; 


