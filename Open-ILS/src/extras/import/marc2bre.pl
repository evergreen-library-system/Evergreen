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
use JSON;
use Data::Dumper;
use Unicode::Normalize;

use Time::HiRes qw/time/;
use Getopt::Long;
use MARC::Batch;
use MARC::File::XML;
use MARC::Charset;
use UNIVERSAL::require;

MARC::Charset->ignore_errors(1);

my ($utf8, $id_field, $count, $user, $password, $config, $keyfile,  @files, @trash_fields) =
	(0, '998', 1, 'admin', 'open-ils', '/openils/conf/bootstrap.conf');

GetOptions(
	'startid=i'	=> \$count,
	'idfield=s'	=> \$id_field,
	'user=s'	=> \$user,
	'password=s'	=> \$password,
	'keyfile=s'	=> \$keyfile,
	'config=s'	=> \$config,
	'file=s'	=> \@files,
	'trash=s'	=> \@trash_fields,
);

@files = @ARGV if (!@files);

my @ses;
my @req;
my %processing_cache;

my %source_map = (      
	o  => 'OCLC',
	i  => 'ISxN',    
	l  => 'LCCN',
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

my %seen;

my $starttime = time;
my $rec;
while ( try { $rec = $batch->next } otherwise { $rec = -1 } ) {
	next if ($rec == -1);
	my $id;

	if ($id_field) {
		my $field = $rec->field($id_field);
		if ($field) {
			if ($field->is_control_field) {
				$id = $field->data;
			} else {
				$id = $field->subfield('a');
			}
		}
	}
		
	if ($id && $id =~ /(\d+)/o) {
		$id = $1;
	} else {
		$id = $count;
	}

	if ($keyfile) {
		if (my $tcn = $keymap{$id}) {
			$rec->delete_field( $_ ) for ($rec->field($id_field));
			$rec->append_fields( MARC::Field->new( $id_field, '', '', 'a', $tcn ) );
		} else {
			$count++;
			next;
		}
	}

	$rec = preprocess($rec);
	$rec->delete_field( $_ ) for ($rec->field($id_field));

	if (!$rec) {
		next;
	}

	my $tcn_value = $rec->subfield('901' => 'a');
	my $tcn_source = $rec->subfield('901' => 'b');

	next if ($seen{$tcn_value});
	$seen{$tcn_value} = 1;

	(my $xml = $rec->as_xml_record()) =~ s/\n//sog;
	$xml =~ s/^<\?xml.+\?\s*>//go;
	$xml =~ s/>\s+</></go;
	$xml =~ s/\p{Cc}//go;
	$xml = entityize($xml);

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
                my $f = $rec->field($id_field);
                $id = $f->subfield('a') if ($f);
        }

	if (!$id) {
		my $f = $rec->field('001');
		$id = $f->data if ($f);
	}

	if (!$id) {
		my $f = $rec->field('000');
		$id = $f->data if ($f);
		$source = 'g'; # only PG seems to use this
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
		$count++;
		warn "\n !!! Record with no TCN : $count\n".$rec->as_formatted;
		return undef;
	}

	$rec->delete_field($_) for ($rec->field($id_field, @trash_fields));

	$id =~ s/\s*$//o;
	$id =~ s/^\s*//o;
	$id =~ s/^(\S+).*$/$1/o;

	$id = $source.$id if ($source);

	($source, $value) = $id =~ /^(.)(.+)$/o;
	if ($id =~ /^o(\d+)$/o) {
		$id = "ocm$1";
		$source = 'o';
	}

	my $tcn = MARC::Field->new(
		'901' => ('', ''),
		a => $id,
		b => do { $source_map{$source} || 'System' },
	);

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

