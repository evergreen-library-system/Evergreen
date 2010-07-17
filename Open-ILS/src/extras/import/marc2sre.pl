#!/usr/bin/perl
use strict;
use warnings;

use lib '/openils/lib/perl5/';

use OpenSRF::System;
use OpenSRF::Application;
use OpenSRF::EX qw/:try/;
use OpenSRF::AppSession;
use OpenSRF::MultiSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::Utils::JSON;
use Data::Dumper;
use Unicode::Normalize;

use Time::HiRes qw/time/;
use Getopt::Long;
use MARC::Batch;
use MARC::File::XML ( BinaryEncoding => 'utf-8' );
use MARC::Charset;

MARC::Charset->ignore_errors(1);

my ($idfield, $count, $user, $password, $config, $marctype, $idsubfield, @files, @trash_fields, $quiet, $libmap) =
	('001', 1, 'admin', 'open-ils', '/openils/conf/opensrf_core.xml', 'USMARC');

GetOptions(
	'idfield=s'	=> \$idfield,
	'idsubfield=s'	=> \$idsubfield,
	'startid=i'	=> \$count,
	'user=s'	=> \$user,
	'password=s'	=> \$password,
	'config=s'	=> \$config,
	'marctype=s'	=> \$marctype,
	'file=s'	=> \@files,
	'libmap=s'	=> \$libmap,
	'quiet'		=> \$quiet,
);

@files = @ARGV if (!@files);

my @ses;
my @req;
my %processing_cache;
my $lib_id_map;
if ($libmap) {
	$lib_id_map = map_libraries_to_ID($libmap);
}

OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

$user = OpenILS::Application::AppUtils->check_user_session( login($user,$password) )->id;

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $batch = new MARC::Batch ( $marctype, @files );
$batch->strict_off();
$batch->warnings_off();

my $starttime = time;
my $rec;
while ( try { $rec = $batch->next } otherwise { $rec = -1 } ) {
	next if ($rec == -1);
	my $id = $count;
	my $record_field;
	if ($idsubfield) {
		$record_field = $rec->field($idfield, $idsubfield);
	} else {
		$record_field = $rec->field($idfield);
	}
	my $record = $count;

	# On some systems, the 001 actually points to the record ID
	# We need to attach to the call number to handle holdings in different libraries
	# but we can work out call numbers later in SQL by the record ID + call number text
	if ($record_field) {
		$record = $record_field->data;
		$record =~ s/^.*?(\d+).*?$/$1/o;
	}

	(my $xml = $rec->as_xml_record()) =~ s/\n//sog;
	$xml =~ s/^<\?xml.+\?\s*>//go;
	$xml =~ s/>\s+</></go;
	$xml =~ s/\p{Cc}//go;
	$xml = OpenILS::Application::AppUtils->entityize($xml);
	$xml =~ s/[\x00-\x1f]//go;

	my $bib = new Fieldmapper::serial::record_entry;
	$bib->id($id);
	$bib->record($record);
	$bib->active('t');
	$bib->deleted('f');
	$bib->marc($xml);
	$bib->creator($user);
	$bib->create_date('now');
	$bib->editor($user);
	$bib->edit_date('now');
	$bib->last_xact_id('IMPORT-'.$starttime);

	if ($libmap) {
		my $lib_id = get_library_id($rec);
		if ($lib_id) {
			$bib->owning_lib($lib_id);
		}
	}

	print OpenSRF::Utils::JSON->perl2JSON($bib)."\n";

	$count++;

	if (!$quiet && !($count % 20)) {
		print STDERR "\r$count\t". $count / (time - $starttime);
	}
}

sub login {        
	my( $username, $password, $type ) = @_;

	$type |= "staff"; 

	my $seed = OpenILS::Application::AppUtils->simplereq(
		'open-ils.auth',
		'open-ils.auth.authenticate.init',
		$username
	);

	die("No auth seed. Couldn't talk to the auth server") unless $seed;

	my $response = OpenILS::Application::AppUtils->simplereq(
		'open-ils.auth',
		'open-ils.auth.authenticate.complete',
                {       username => $username,
                        password => md5_hex($seed . md5_hex($password)),
                        type => $type });

        die("No auth response returned on login.") unless $response;

        my $authtime = $response->{payload}->{authtime};
        my $authtoken = $response->{payload}->{authtoken};

	die("Login failed for user $username!") unless $authtoken;

        return $authtoken;
}       

=head2

map_libraries_to_ID

Parses a file to return a hash of library names to integers representing
the actor.org_unit.id value of the library. This enables us to generate
an ingest file that does not subsequently need to manually manipulated.

The library name must correspond to the 'b' subfield of the 852 field.
Well, it does not have to, but you will have to modify this script
accordingly.

The format of the map file should be the name of the library, followed
by a tab, followed by the desired numeric ID of the library. For example:

BR1	4
BR2	5

=cut

sub map_libraries_to_ID {
	my $map_filename = shift;

	my %lib_id_map;

	open(MAP_FH, '<', $map_filename) or die "Could not load [$map_filename] $!";
	while (<MAP_FH>) {
		my ($lib, $id) = $_ =~ /^(.*?)\t(.*?)$/;
		$lib_id_map{$lib} = $id;
	}

	return \%lib_id_map;
}

sub get_library_id {
	my $record = shift;

	my $lib_name = $record->field('852')->subfield('b');
	my $lib_id = $lib_id_map->{$lib_name};

	return $lib_id;
}
