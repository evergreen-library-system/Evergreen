#!/usr/bin/perl -w
use strict;
use UNIVERSAL::require;
use MARC::Charset;
use MARC::Batch;
use MARC::File::XML;
use Time::HiRes qw/time/;
use Getopt::Long;
use Data::Dumper;
use Error qw/:try/;
use DBI;
use open qw/:utf8/;

#-------------------------------------------------------------------------------
#  The keys of this hash should be the string values stored in your legacy
#  system that map to the copy statuses in Open-ILS.  If you don't see a
#  legacy status here that you need to carry over to your new Open-ILS install
#  you can use the "Copy Statuses" bootstrapping CGI to create an entry for it.
#  Then simply a key for the legacy status that points to the SysID of the new
#  Open-ILS Copy Status.
#-------------------------------------------------------------------------------
my %status_map = (
	''		=> 0,
	CHECKEDOUT	=> 1,
	BINDERY		=> 2,
	LOST		=> 3,
	MISSING		=> 4,
	INPROCESS	=> 5,
	INTRANSIT	=> 6,
	RESHELVING	=> 7,
	'ON HOLDS SHELF'=> 8,
	'ON-ORDER'	=> 9,
	ILL		=> 10,
	CATALOGING	=> 11,
	RESERVES	=> 12,
	DISCARD		=> 13,
);


$|=1;

my ($userid,$cn_id,$cp_id,$cp_file,$cn_file,$lib_map_field,$id_tag,$id_field,$id_subfield, $marc_file) =
	(1, 1, 1, 'asset_copy.sql','asset_volume.sql','shortname','001');

my ($skip,$enc,$marctype,$holding_tag,$bc,$lbl,$own,$pr,$cpn,$avail) =
	(0,'utf-8','XML','999','i','a','m','p','c','k');

my ($db_driver,$db_host,$db_name,$db_user,$db_pw) =
	('Pg','localhost','evergreen','postgres','postgres');

GetOptions (	
	"encoding=s"		=> \$enc,
	"copy_file=s"		=> \$cp_file,
	"volume_file=s"		=> \$cn_file,
	"userid=i"		=> \$userid,
	"first_volume=i"	=> \$cn_id,
	"first_copy=i"		=> \$cp_id,
	"db_driver=s"		=> \$db_driver,
	"db_host=s"		=> \$db_host,
	"db_name=s"		=> \$db_name,
	"db_user=s"		=> \$db_user,
	"db_pw=s"		=> \$db_pw,
	"lib_map_field=s"	=> \$lib_map_field,
	"id_field=s"		=> \$id_field,
	"id_subfield=s"		=> \$id_subfield,
	"holding_field=s"	=> \$holding_tag,
	"item_barcode=s"	=> \$bc,
	"item_call_number=s"	=> \$lbl,
	"item_owning_lib=s"	=> \$own,
	"item_price=s"		=> \$pr,
	"item_copy_number=s"	=> \$cpn,
	"item_copy_status=s"	=> \$avail,
	"marc_file=s"		=> \$marc_file,
	"marctype=s"		=> \$marctype,
	"skip=i"		=> \$skip,

);

if ($marctype eq 'XML') {
	'open'->use(':utf8');
} else {
        bytes->use();
}

if ($enc) {
	MARC::Charset->ignore_errors(1);
        MARC::Charset->assume_encoding($enc);
}

my $dsn = "dbi:$db_driver:host=$db_host;dbname=$db_name";
my $dbh = DBI->connect($dsn,$db_user,$db_pw);

my $t = 'actor_org_unit';
if ($db_driver eq 'Pg') {
	$t = 'actor.org_unit';
}
my $sth = $dbh->prepare("SELECT $lib_map_field,id FROM $t");
$sth->execute;

my $lib_map = {};
while (my $lib = $sth->fetchrow_arrayref) {
	$$lib_map{$$lib[0]} = $$lib[1];
}

my $tcn_sth = $dbh->prepare("SELECT id FROM biblio.record_entry WHERE tcn_value = ?");
my $rec_id;

open CP, ">>$cp_file" or die "Can't open $cp_file!  $!\n";
open CN, ">>$cn_file" or die "Can't open $cn_file!  $!\n";

print CP <<SQL if (!$skip);
SET CLIENT_ENCODING TO 'UNICODE';
COPY asset.copy (id,circ_lib,editor,creator,barcode,call_number,copy_number,status,loan_duration,fine_level,circulate,deposit,deposit_amount,price,ref,opac_visible) FROM STDIN;
SQL

print CN <<SQL if (!$skip);
SET CLIENT_ENCODING TO 'UNICODE';
COPY asset.call_number (id,editor,creator,record,label,owning_lib) FROM STDIN;
SQL

my $xact_id = time;

my $batch = MARC::Batch->new( $marctype => $marc_file );
$batch->strict_off();
$batch->warnings_off();

my $cn_map;
my $count = 0;
my $record;
while ( try { $record = $batch->next } otherwise { $record = -1 } ) {
	next if ($record == -1);
	$count++;
	next if ($count <= $skip);

	$rec_id = $record->subfield( $id_field => $id_subfield );

	next unless ($rec_id);

	for my $field ($record->field($holding_tag)) {
		my $barcode = $field->subfield( $bc );
		my $label = $field->subfield( $lbl );
		my $owning_lib = $$lib_map{ $field->subfield( $own ) };
		my $price = $field->subfield( $pr );
		my $copy_number = $field->subfield( $cpn ) || '\N';
		my $available = $field->subfield( $avail ) || '';

		my $status = $status_map{$available} || 0;

		next unless $barcode;
		next unless $owning_lib;
		next unless $label;

		$barcode =~ s/\\/\\\\/og;
		$label =~ s/\\/\\\\/og;
		$price =~ s/\$//og if($price);
		if (!defined($price) || $price !~ /^\s*\d{1,6}\.\d{2}\s*$/o) {
			$price = '0.00';
		}

		unless (exists($$cn_map{"$rec_id/$owning_lib/$label"})) {
			$$cn_map{"$rec_id/$owning_lib/$label"} = $cn_id;
			print CN join("\t",($cn_id,$userid,$userid,$rec_id,$label,$owning_lib))."\n";
			print 'v';
			$cn_id++;
		}

# id,editor,creator,barcode,call_number,copy_number,available,loan_duration,fine_level,circulate,deposit,deposit_amount,price,ref,opac_visible

		print CP join("\t", (	$cp_id,$owning_lib,$userid,$userid,$barcode,
					$$cn_map{"$rec_id/$owning_lib/$label"},
					$copy_number,$status,2,2,1,0,'0.00',
					$price,0,1 )
			 )."\n";
		print 'c';
		$cp_id++;
	}
}

print CN "\\.\n";
print CN "SELECT setval('asset.call_number_id_seq'::TEXT, $cn_id);\n";
print CP "\\.\n";
print CP "SELECT setval('asset.copy_id_seq'::TEXT, $cp_id);\n";

