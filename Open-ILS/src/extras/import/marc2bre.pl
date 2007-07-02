#!/usr/bin/perl
use strict;
use warnings;

use lib '/openils/lib/perl5/';

use Error qw/:try/;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::Utils::JSON;
use Data::Dumper;
use Unicode::Normalize;
use Encode;

use FileHandle;
use Time::HiRes qw/time/;
use Getopt::Long;
use MARC::Batch;
use MARC::File::XML ( BinaryEncoding => 'utf-8' );
use MARC::Charset;

#MARC::Charset->ignore_errors(1);

my ($id_field, $recid, $user, $config, $idlfile, $marctype, $keyfile, $dontuse_file, $enc, $force_enc, @files, @trash_fields) =
	('', 1, 1, '/openils/conf/opensrf_core.xml', '/openils/conf/fm_IDL.xml', 'USMARC');

GetOptions(
	'marctype=s'	=> \$marctype,
	'startid=i'	=> \$recid,
	'idfield=s'	=> \$id_field,
	'user=s'	=> \$user,
	'encoding=s'	=> \$enc,
	'hard_encoding'	=> \$force_enc,
	'keyfile=s'	=> \$keyfile,
	'config=s'	=> \$config,
	'file=s'	=> \@files,
	'trash=s'	=> \@trash_fields,
	'xml_idl=s'	=> \$idlfile,
	'dontuse=s'	=> \$dontuse_file
);

if ($enc) {
	MARC::Charset->ignore_errors(1);
	MARC::Charset->assume_encoding($enc);
}

if (uc($marctype) eq 'XML') {
	'open'->use(':utf8');
} else {
	bytes->use();
}

@files = @ARGV if (!@files);

my @ses;
my @req;
my %processing_cache;

my $startid = $recid;

my %source_map = (      
	o  => 'OCLC',
	i  => 'ISxN',    
	l  => 'LCCN',
	s  => 'System',  
	g  => 'Gutenberg',  
);                              



Fieldmapper->import(IDL => $idlfile);

my %keymap;
if ($keyfile) {
	open F, $keyfile or die "Couldn't open key file $keyfile";
	while (<F>) {
		if ( /^(\d+)\|(\S+)/o ) {
			$keymap{$1} = $2;
		}
	}
	close(F);
}

my %dontuse_id;
if ($dontuse_file) {
	open F, $dontuse_file or die "Couldn't open used-id file $dontuse_file";
	while (<F>) {
		chomp;
		s/^\s*//;
		s/\s*$//;
		$dontuse_id{$_} = 1;
	}
	close(F);
}

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $batch = new MARC::Batch ( $marctype, @files );
$batch->strict_off();
$batch->warnings_off();

my %used_ids;
my $starttime = time;
my $rec;
my $count = 0;
while ( try { $rec = $batch->next } otherwise { $rec = -1 } ) {
	next if ($rec == -1);
	my $id;

	$recid++;
	while ($used_ids{$recid}) {
		$recid++;
	}
	$used_ids{$recid} = 1;

	if ($id_field) {
		my $field = $rec->field($id_field);
		if ($field) {
			if ($field->is_control_field) {
				$id = $field->data;
			} else {
				$id = $field->subfield('a');
			}

			$id =~ s/\D+//gso;
		}
	}

	if (!$id) {
		$id = $recid;
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

	my $tcn;
	($rec, $tcn) = preprocess($rec);
	$rec->delete_field( $_ ) for ($rec->field($id_field));
	$rec->append_fields( $tcn );

	if (!$rec) {
		next;
	}

	my $tcn_value = $rec->subfield('901' => 'a') || "SYS$id";
	my $tcn_source = $rec->subfield('901' => 'b') || 'System';

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

	print OpenSRF::Utils::JSON->perl2JSON($bib)."\n";
	$dontuse_id{$tcn_value} = 1;

	$count++;

	if (!($count % 50)) {
		print STDERR "\r$count\t". $count / (time - $starttime);
	}
}

sub preprocess {
	my $rec = shift;

	my ($id, $source, $value) = ('','','');

	if (!$id) {
		my $f = $rec->field('001');
		$id = $f->data if ($f);
	}

	if (!$id || $dontuse_id{$source.$id}) {
		my $f = $rec->field('000');
		$id = $f->data if ($f);
		$source = 'g' if ($f); # only PG seems to use this
	}

        if (!$id || $dontuse_id{$source.$id}) {
                my $f = $rec->field('020');
                $id = $f->subfield('a') if ($f);
		$source = 'i' if ($f);
        }

        if (!$id || $dontuse_id{$source.$id}) {
                my $f = $rec->field('022');
                $id = $f->subfield('a') if ($f);
		$source = 'i' if ($f);
        }

        if (!$id || $dontuse_id{$source.$id}) {
                my $f = $rec->field('010');
                $id = $f->subfield('a') if ($f);
		$source = 'l' if ($f);
        }

#        if (!$id) {
#                my $f = $rec->field($id_field);
#                $id = $f->subfield('a') if ($f);
#        }

	$rec->delete_field($_) for ($rec->field($id_field, @trash_fields));

	if ($id) {
		$id =~ s/\s*$//o;
		$id =~ s/^\s*//o;
		$id =~ s/^(\S+).*$/$1/o;

		$id = $source.$id if ($source);

		($source, $value) = $id =~ /^(.)(.+)$/o;
		if ($id =~ /^o(\d+)$/o) {
			$id = "ocm$1";
			$source = 'o';
		}
	}

	if ($id && $dontuse_id{$id}) {
		warn "\n!!! ID $id is already in use\n";
		$id = '';
	}

	if (!$id) {
		$source = 's';
		$id = 's'.$recid;
	}

	my $tcn = MARC::Field->new(
		'901' => ('', ''),
		a => $id,
		b => do { $source_map{$source} || 'System' },
	);

	return ($rec,$tcn);
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

