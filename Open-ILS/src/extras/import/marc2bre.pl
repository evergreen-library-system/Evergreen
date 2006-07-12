#!/usr/bin/perl
use strict;
use warnings;

use lib '/openils/lib/perl5/';

#use OpenSRF::System;
#use OpenILS::Utils::Fieldmapper;
#use OpenSRF::Utils::SettingsClient;
#
#OpenSRF::System->bootstrap_client(config_file =>
#'/openils/conf/bootstrap.conf');
#Fieldmapper->import(IDL =>
#  OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
#
#  # do this after bootstrapping/importing IDL
#  require OpenILS::Application::Search;
#
#  my $meth = OpenSRF::Application->method_lookup(
#    'open-ils.search.biblio.metarecord.mods_slim.retrieve');
#    my @data = $meth->run(1);
#    my $mods = shift @data;
#    print "Got mvr: " . $mods->title . "\n";



use OpenSRF::System;
use OpenSRF::Application;
use OpenSRF::EX qw/:try/;
use OpenSRF::AppSession;
use OpenSRF::MultiSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;
use JSON;
use Data::Dumper;

use Time::HiRes qw/time/;
use Getopt::Long;
use MARC::Batch;
use MARC::File::XML;
use MARC::Charset;
use UNIVERSAL::require;

MARC::Charset->ignore_errors(1);

my ($id_field, $count, $user, $password, $config, $keyfile,  @files) =
	('998', 1, 'admin', 'open-ils', '/openils/conf/bootstrap.conf');

GetOptions(
	'startid=i'	=> \$count,
	'idfield=s'	=> \$id_field,
	'user=s'	=> \$user,
	'password=s'	=> \$password,
	'keyfile=s'	=> \$keyfile,
	'config=s'	=> \$config,
	'file=s'	=> \@files,
);

@files = @ARGV if (!@files);

my @ses;
my @req;
my %processing_cache;

my %source_map = (      
	o  => 'OCLC',
	i  => 'ISxN',    
	l  => 'Local',
	s  => 'System',  
	g  => 'Gutenberg',  
);                              


OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

$user = OpenILS::Application::AppUtils->check_user_session( login($user,$password) )->id;

my %keymap;
if ($keyfile) {
	open F, $keyfile or die "Couldn't open key file $keyfile";
	while (<F>) {
		if ( /^(\d+)\|(\S+)/o ) {
			$keymap{$1} = $2;
		}
	}
}

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $batch = new MARC::Batch ( 'USMARC', @files );
$batch->strict_off();
$batch->warnings_off();

my $starttime = time;
while ( my $rec = $batch->next ) {

	my $id = $rec->subfield($id_field => 'a') || $count;
	if ($id =~ /(\d+)/o) {
		$id = $1;
	}

	if ($keyfile) {
		if (my $tcn = $keymap{$id}) {
			$rec->delete_field( $_ ) for ($rec->field('035'));
			$rec->append_fields( MARC::Field->new( '035', '', '', 'a', $tcn ) );
		} else {
			$count++;
			next;
		}
	}

	$rec = preprocess($rec, $id);

	if (!$rec) {
		next;
	}

	my $tcn_value = $rec->subfield('039' => 'a');
	my $tcn_source = $rec->subfield('039' => 'b');

	(my $xml = $rec->as_xml_record()) =~ s/\n//sog;
	$xml =~ s/^<\?xml.+\?\s*>//go;
	$xml =~ s/>\s+</></go;

	my $bib = new Fieldmapper::biblio::record_entry;
	$bib->id($id);
	$bib->active('t');
	$bib->deleted('f');
	$bib->marc($xml);
	$bib->creator($user);
	$bib->create_date('now');
	$bib->editor($user);
	$bib->edit_date('now');
	$bib->tcn_source($tcn_source);
	$bib->tcn_value($tcn_value);
	$bib->last_xact_id('IMPORT-'.$starttime);

	print JSON->perl2JSON($bib)."\n";

	$count++;

	if (!($count % 20)) {
		print STDERR "\r$count\t". $count / (time - $starttime);
	}
}

sub preprocess {
	my $rec = shift;

	my ($id, $source, $value);

	if (!$id) {
		my $f = $rec->field('001');
		$id = $f->data if ($f);
	}

	if (!$id) {
		my $f = $rec->field('000');
		$id = 'g'.$f->data if ($f);
		$source = 'g';
	}

        if (!$id) {
                my $f = $rec->field('020');
                $id = $f->subfield('a') if ($f);
		$source = 'i';
        }

        if (!$id) {
                my $f = $rec->field('022');
                $id = $f->subfield('a') if ($f);
		$source = 'i';
        }

        if (!$id) {
                my $f = $rec->field('010');
                $id = $f->subfield('a') if ($f);
		$source = 'l';
        }

        if (!$id) {
                my $f = $rec->field('035');
                $id = $f->subfield('a') if ($f);
		$source = 's';
        }

	if (!$id) {
		$count++;
		warn "\n !!! Record with no TCN : $count\n".$rec->as_formatted;
		return undef;
	}

	$id =~ s/\s*$//o;
	$id =~ s/^\s*//o;
	$id =~ s/(\S+)$/$1/o;

	$id = $source.$id if ($source);

	($source, $value) = $id =~ /^(.)(.+)$/o;
	if ($id =~ /^o(\d+)$/o) {
		$id = "ocm$1";
		$source = 'o';
	}

	my $tcn = MARC::Field->new(
		'039',
		'', '',
		'a', $id,
		'b', do { $source_map{$source} || 'System' },
	);

	$rec->delete_field($_) for ($rec->field('035','948','998'));
	$rec->append_fields($tcn);

	return $rec;
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

