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

my ($utf8, $id_field, $count, $user, $password, $config, $marctype, $keyfile,  @files, @trash_fields, $quiet) =
	(0, '998', 1, 'admin', 'open-ils', '/openils/conf/opensrf_core.xml', 'USMARC');

GetOptions(
	'startid=i'	=> \$count,
	'user=s'	=> \$user,
	'marctype=s'	=> \$marctype,
	'password=s'	=> \$password,
	'config=s'	=> \$config,
	'file=s'	=> \@files,
	'quiet'		=> \$quiet,
);

@files = @ARGV if (!@files);

my @ses;
my @req;
my %processing_cache;

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
	my $_001 = $rec->field('001');
	my $arn = $count;
	$arn = $_001->data if ($_001);

	(my $xml = $rec->as_xml_record()) =~ s/\n//sog;
	$xml =~ s/^<\?xml.+\?\s*>//go;
	$xml =~ s/>\s+</></go;
	$xml =~ s/\p{Cc}//go;
	$xml = entityize($xml,'D');
	$xml =~ s/[\x00-\x1f]//go;

	my $bib = new Fieldmapper::authority::record_entry;
	$bib->id($id);
	$bib->active('t');
	$bib->deleted('f');
	$bib->marc($xml);
	$bib->creator($user);
	$bib->create_date('now');
	$bib->editor($user);
	$bib->edit_date('now');
	$bib->arn_source('LEGACY');
	$bib->arn_value($arn);
	$bib->last_xact_id('IMPORT-'.$starttime);

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

sub entityize {
        my $stuff = shift;
        my $form = shift;

        if ($form and $form eq 'D') {
                $stuff = NFD($stuff);
        } else {
                $stuff = NFC($stuff);
        }

        $stuff =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
        return $stuff;
}

