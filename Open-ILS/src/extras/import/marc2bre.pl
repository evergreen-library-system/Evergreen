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
use DBI;

#MARC::Charset->ignore_errors(1);

my ($id_field, $id_subfield, $recid, $user, $config, $idlfile, $marctype, $tcn_offset, $tcn_mapfile, $tcn_dumpfile, $used_id_file, $used_tcn_file, $enc, @files, @trash_fields, @req_fields, $use901, $quiet, $tcn_field, $tcn_subfield) =
	('', 'a', 0, 1, '/openils/conf/opensrf_core.xml', '/openils/conf/fm_IDL.xml', 'USMARC', 0);

my ($db_driver, $db_host, $db_port, $db_name, $db_user, $db_pw) =
	('Pg', 'localhost', 5432, 'evergreen', 'postgres', 'postgres');

GetOptions(
	'marctype=s'	=> \$marctype, # format of MARC files being processed defaults to USMARC, often set to XML
	'startid=i'	=> \$recid, # id number to start with when auto-assigning id numbers, defaults to highest id in database + 1
	'idfield=s'	=> \$id_field, # field containing the record's desired internal id, NOT tcn
	'idsubfield=s'	=> \$id_subfield, # subfield of above record id field
	'tcnfield=s'	=> \$tcn_field, # field containing the record's desired tcn, NOT the internal id
	'tcnsubfield=s'	=> \$tcn_subfield, # subfield of above record tcn field
	'tcnoffset=i'	=> \$tcn_offset, # optionally skip characters at beginning of supplied tcn (e.g. to remove '(Sirsi)')
	'user=s'	=> \$user, # set creator/editor values for records in database
	'encoding=s'	=> \$enc, # set assumed MARC encoding for MARC::Charset
	'keyfile=s'	=> \$tcn_mapfile, # DEPRECATED, use tcn_mapfile instead
	'tcn_mapfile=s'	=> \$tcn_mapfile, # external file which allows for matching specific record tcns to specific record ids, format = one id_number|tcn_number combo per line
	'tcnfile=s'	=> \$tcn_dumpfile, # DEPRECATED, use tcn_dumpfile instead
	'tcn_dumpfile=s'	=> \$tcn_dumpfile, # allows specification of a dumpfile for all used tcn values
	'config=s'	=> \$config, # location of OpenSRF core config file, defaults to /openils/conf/opensrf_core.xml
	'file=s'	=> \@files, # files to process (or you can simple list the files as unnamed arguments, i.e. @ARGV)
	'required_fields=s'	=> \@req_fields, # skip any records missing these fields
	'trash=s'	=> \@trash_fields, # fields to remove from all processed records
	'xml_idl=s'	=> \$idlfile, # location of XML IDL file, defaults to /openils/conf/fm_IDL.xml
	'dontuse=s'	=> \$used_id_file, # DEPRECATED, use used_id_file instead
	'used_id_file=s'	=> \$used_id_file, # external file which prevents id collisions by specifying ids already in use in the database, format = one id number per line
	'used_tcn_file=s'	=> \$used_tcn_file, # external file which prevents tcn collisions by specifying tcns already in use in the database, format = one tcn number per line
	"db_driver=s"	=> \$db_driver, # database driver type, usually 'Pg'
	"db_host=s"	=> \$db_host, # database hostname
	"db_port=i"	=> \$db_port, # database port
	"db_name=s"	=> \$db_name, # database name
	"db_user=s"	=> \$db_user, # database username
	"db_pw=s"	=> \$db_pw, # database password
	'use901'	=> \$use901, # use values from previously created 901 fields and skip all other processing
	'quiet'		=> \$quiet # do not output progress count
);

@trash_fields = split(/,/,join(',',@trash_fields));
@req_fields = split(/,/,join(',',@req_fields));

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

my $dsn = "dbi:$db_driver:host=$db_host;port=$db_port;dbname=$db_name";

if (!$recid) {
    my $table = 'biblio_record_entry';
    $table = 'biblio.record_entry' if ($db_driver eq 'Pg');

	my $dbh = DBI->connect($dsn,$db_user,$db_pw);
	my $sth = $dbh->prepare("SELECT MAX(id) + 1 FROM $table");

	$sth->execute;
	$sth->bind_col(1, \$recid);
	$sth->fetch;
	$sth->finish;
	$dbh->disconnect;

	# In a clean Evergreen schema, the maximum ID will be -1; but sequences
	# have to start at 1, so handle the clean Evergreen schema situation
	if ($recid == 0) {
		$recid = 1;
	}
}

my %tcn_source_map = (
	a  => 'Sirsi_Auto',
	o  => 'OCLC',
	i  => 'ISxN',
	l  => 'LCCN',
	s  => 'System',
	g  => 'Gutenberg',
	z  => 'Unknown',
);

Fieldmapper->import(IDL => $idlfile);

my %tcn_map;
if ($tcn_mapfile) {
	open F, $tcn_mapfile or die "Couldn't open key file $tcn_mapfile";
	while (<F>) {
		if ( /^(\d+)\|(\S+)/o ) {
			$tcn_map{$1} = $2;
		}
	}
	close(F);
}

my %used_recids;
if ($used_id_file) {
	open F, $used_id_file or die "Couldn't open used-id file $used_id_file";
	while (<F>) {
		chomp;
		s/^\s*//;
		s/\s*$//;
		$used_recids{$_} = 1;
	}
	close(F);
}

my %used_tcns;
if ($used_tcn_file) {
	open F, $used_tcn_file or die "Couldn't open used-tcn file $used_tcn_file";
	while (<F>) {
		chomp;
		s/^\s*//;
		s/\s*$//;
		$used_tcns{$_} = 1;
	}
	close(F);
}

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $batch = new MARC::Batch ( $marctype, @files );
$batch->strict_off();
$batch->warnings_off();

my $starttime = time;
my $rec;
my $count = 0;
PROCESS: while ( try { $rec = $batch->next } otherwise { $rec = -1 } ) {
	next if ($rec == -1);

	$count++;

	# Skip records that don't contain a required field (like '245', for example)
	foreach my $req_field (@req_fields) {
		if (!$rec->field("$req_field")) {
			warn "\n!!! Record $count missing required field $req_field, skipping record.\n";
			next PROCESS;
		}
	}

	my $id;
	my $tcn_value = '';
	my $tcn_source = '';
	# If $use901 is set, use it for the id, the tcn, and the tcn source without ANY further processing (i.e. no error checking)
	if ($use901) {
		$rec->delete_field($_) for ($rec->field(@trash_fields));
		$tcn_value = $rec->subfield('901' => 'a');
		$tcn_source = $rec->subfield('901' => 'b');
		$id = $rec->subfield('901' => 'c');
	} else {
		# This section of code deals with the record's 'id', which is a system-level, numeric, internal identifier
		# It is often convenient but not necessary to carry over the internal ids from your previous ILS, so here is where that happens
		if ($id_field) {
			my $field = $rec->field($id_field);
			if ($field) {
				if ($field->is_control_field) {
					$id = $field->data;
				} else {
					$id = $field->subfield($id_subfield);
				}
				# ensure internal record ids are numeric only
				$id =~ s/\D+//gso if $id;
			}

			# catch problem ids
			if (!$id) {
				warn "\n!!! Record $count has missing or invalid id field $id_field, assinging new id.\n";
				$id = '';
			} elsif (exists $used_recids{$id}) {
				warn "\n!!! Record $count has a duplicate id in field $id_field, assinging new id.\n";
				$id = '';
			} else {
				$used_recids{$id} = 1;
			}
		}

		# id field not specified or found to be invalid, assign auto id
		if (!$id) {
			while (exists $used_recids{$recid}) {
				$recid++;
			}
			$used_recids{$recid} = 1;
			$id = $recid;
			$recid++;
		}

		# This section of code deals with the record's 'tcn', or title control number, which is a record-level, possibly alpha-numeric, sometimes user-supplied value
		if ($tcn_field) {
			if ($tcn_mapfile) {
				if (my $tcn = $tcn_map{$id}) {
					$rec->delete_field( $_ ) for ($rec->field($tcn_field));
					$rec->append_fields( MARC::Field->new( $tcn_field, '', '', $tcn_subfield, $tcn ) );
				} else {
					warn "\n!!! ID $id not found in tcn_mapfile, skipping record.\n";
					$count++;
					next;
				}
			}

			my $field = $rec->field($tcn_field);
			if ($field) {
				if ($field->is_control_field) {
					$tcn_value = $field->data;
				} else {
					$tcn_value = $field->subfield($tcn_subfield);
				}
				# $tcn_offset is another Sirsi influence, as it will allow you to remove '(Sirsi)'
				# from exported tcns, but was added more generically to perhaps support other use cases
				if ($tcn_value) { 
					$tcn_value = substr($tcn_value, $tcn_offset);
				} else {
					$tcn_value = '';
				}
			}
		}

		# turn our id and tcn into a 901 field, and also create a tcn and/or figure out the tcn source
		my $field901;
		($field901, $tcn_value, $tcn_source) = preprocess($rec, $tcn_value, $id);
		# delete the old identifier and trash fields
		$rec->delete_field($_) for ($rec->field('901', $tcn_field, $id_field, @trash_fields));
		$rec->append_fields($field901);
	}

	(my $xml = $rec->as_xml_record()) =~ s/\n//sog;
	$xml =~ s/^<\?xml.+\?\s*>//go;
	$xml =~ s/>\s+</></go;
	$xml =~ s/\p{Cc}//go;
	$xml = entityize($xml,'D');
	$xml =~ s/[\x00-\x1f]//go;

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
	$used_tcns{$tcn_value} = 1;

	if (!$quiet && !($count % 50)) {
		print STDERR "\r$count\t". $count / (time - $starttime);
	}
}

if ($tcn_dumpfile) {
    open TCN_DUMPFILE, '>', $tcn_dumpfile;
    print TCN_DUMPFILE "$_\n" for (keys %used_tcns);
}


sub preprocess {
	my $rec = shift;
	my $tcn_value = shift;
	my $id = shift;

	my $tcn_source = '';
	# in the following code, $tcn_number represents the portion of the tcn following the source code-letter
	my $tcn_number = '';
	my $warn = 0;
	my $passed_tcn = '';

	# this preprocess subroutine is optimized for Sirsi-created tcns, that is, those with a single letter
	# followed by some digits (and maybe 'x' in older systems).  If using user supplied tcns, try to identify
	# the source here, otherwise set to 'z' ('Unknown')
	if ($tcn_value =~ /([a-z])([0-9xX]+)/) {
		$tcn_source = $1;
		$tcn_number = $2;
	} else {
		$tcn_source = 'z';
	}
	
	# save and warn if a passed in TCN is replaced	
	if ($tcn_value && exists $used_tcns{$tcn_value}) {
		$passed_tcn = $tcn_value;
		$tcn_value = '';
		$tcn_number = '';
		$tcn_source = '';
		$warn = 1;
	} 

	# we didn't have a user supplied tcn, or it was a duplicate, so let's derive one from commonly unique record fields
	if (!$tcn_value) {
		my $f = $rec->field('001');
		$tcn_value = despace($f->data) if ($f);
	}

	if (!$tcn_value || exists $used_tcns{$tcn_value}) {
		my $f = $rec->field('000');
		if ($f) {
			$tcn_number = despace($f->data);
			$tcn_source = 'g'; # only Project Gutenberg seems to use this
			$tcn_value = $tcn_source.$tcn_number;
		}
	}

    if (!$tcn_value || exists $used_tcns{$tcn_value}) {
        my $f = $rec->field('020');
		if ($f) {	
			$tcn_number = despace($f->subfield('a'));
			$tcn_source = 'i';
			$tcn_value = $tcn_source.$tcn_number;
		}
    }

    if (!$tcn_value || exists $used_tcns{$tcn_value}) {
        my $f = $rec->field('022');
		if ($f) {	
			$tcn_number = despace($f->subfield('a'));
			$tcn_source = 'i';
			$tcn_value = $tcn_source.$tcn_number;
		}
    }

    if (!$tcn_value || exists $used_tcns{$tcn_value}) {
        my $f = $rec->field('010');
		if ($f) {	
			$tcn_number = despace($f->subfield('a'));
			$tcn_source = 'l';
			$tcn_value = $tcn_source.$tcn_number;
		}
    }

    if (!$tcn_value || exists $used_tcns{$tcn_value}) {
		$tcn_source = 's';
		$tcn_number = $id;
		$tcn_value = $tcn_source.$tcn_number;
    }

	# special case to catch possibly passed in full OCLC numbers and those derived from the 001 field
	if ($tcn_value =~ /^oc(m|n)(\d+)$/o) {
		$tcn_source = 'o';
		$tcn_number = $2;
		$tcn_value = $tcn_source.$tcn_number;
	}

	# expand $tcn_source from code letter to full name
	$tcn_source = do { $tcn_source_map{$tcn_source} || 'Unknown' };

	if ($warn) {
		warn "\n!!! TCN $passed_tcn is already in use, using TCN ($tcn_value) derived from $tcn_source ID.\n";
	}

	my $field901 = MARC::Field->new(
		'901' => ('', ''),
		a => $tcn_value,
		b => $tcn_source,
		c => $id
	);

	return ($field901, $tcn_value, $tcn_source);
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

sub despace {
	my $value = shift;

	# remove all leading/trailing spaces and trucate at first internal space if present
	$value =~ s/\s*$//o;
	$value =~ s/^\s*//o;
	$value =~ s/^(\S+).*$/$1/o;

	return $value;
}
