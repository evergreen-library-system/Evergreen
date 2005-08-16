#!/usr/bin/perl -w
use strict;
use XML::LibXML;
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

my ($userid,$cn_id,$cp_id,$cp_file,$cn_file,$map_file,$lib_map_field,$id_tag) =
	(1, 1, 1, 'asset_copy.sql','asset_volume.sql','record_id_map.pl','shortname','/*/*/*[@tag="035"][1]');

my ($holding_tag,$bc,$lbl,$own,$pr,$cpn,$avail) =
	('/*/*/*[@tag="999"]','i','a','m','p','c','k');

my ($db_driver,$db_host,$db_name,$db_user,$db_pw) =
	('Pg','localhost','demo-dev','postgres','postgres');

GetOptions (	
	"copy_file=s"		=> \$cp_file,
	"volume_file=s"		=> \$cn_file,
	"tcn_map_file=s"	=> \$map_file,
	"userid=i"		=> \$userid,
	"first_volume=i"	=> \$cn_id,
	"first_copy=i"		=> \$cp_id,
	"db_driver=s"		=> \$db_driver,
	"db_host=s"		=> \$db_host,
	"db_name=s"		=> \$db_name,
	"db_user=s"		=> \$db_user,
	"db_pw=s"		=> \$db_pw,
	"lib_map_field=s"	=> \$lib_map_field,
	"id_tag_xpath=s"	=> \$id_tag,
	"holding_tag_xpath=s"	=> \$holding_tag,
	"item_barcode=s"	=> \$bc,
	"item_call_number=s"	=> \$lbl,
	"item_owning_lib=s"	=> \$own,
	"item_price=s"		=> \$pr,
	"item_copy_number=s"	=> \$cpn,
	"item_copy_status=s"	=> \$avail,

);

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
	
my $tcn_map;
eval `cat $map_file`;

open CP, ">$cp_file" or die "Can't open $cp_file!  $!\n";
open CN, ">$cn_file" or die "Can't open $cn_file!  $!\n";


print CP <<SQL;
SET CLIENT_ENCODING TO 'UNICODE';
COPY asset.copy (id,circ_lib,editor,creator,barcode,call_number,copy_number,status,loan_duration,fine_level,circulate,deposit,deposit_amount,price,ref,opac_visible) FROM STDIN;
SQL

print CN <<SQL;
SET CLIENT_ENCODING TO 'UNICODE';
COPY asset.call_number (id,editor,creator,record,label,owning_lib) FROM STDIN;
SQL

my $xact_id = time;

my $parser = XML::LibXML->new;

my $cn_map;

my $xml = '';
while ( $xml .= <STDIN> ) {
	chomp $xml;
	next unless $xml;

	my $tcn;
	my $doc;
	my $success = 0;
	try {
		$doc = $parser->parse_string($xml);;
		$tcn = $doc->documentElement->findvalue( '/*/*[@tag="035"][1]' );
		$success = 1;
	} catch Error with {
		my $e = shift;
		warn $e;
		warn $xml;
	};	
	next unless $success;

	$tcn =~ s/^.*?(\w+)\s*$/$1/go;
	
	unless ($tcn) {
		warn "\nNo TCN found in rec!!\n";
		$xml = '';
		next;
	}

	unless (exists($$tcn_map{$tcn})) {
		warn "\n !! TCN $tcn not in the map!\n";
		$xml = '';
		next;
	}

	my $rec_id = $$tcn_map{$tcn};

	for my $node ($doc->documentElement->findnodes($holding_tag)) {
		my $barcode = $node->findvalue( "*[\@code=\"$bc\"]" );
		my $label = $node->findvalue( "*[\@code=\"$lbl\"]" );
		my $owning_lib = $$lib_map{ $node->findvalue( "*[\@code=\"$own\"]" ) };
		my $price = $node->findvalue( "*[\@code=\"$pr\"]" );
		my $copy_number = $node->findvalue( "*[\@code=\"$cpn\"]" ) || 0;
		my $available = $node->findvalue( "*[\@code=\"$avail\"]" ) || '';

		my $status = $status_map{$available} || 0;

		next unless $barcode;
		next unless $owning_lib;
		next unless $label;

		$barcode =~ s/\\/\\\\/og;
		$label =~ s/\\/\\\\/og;
		$price =~ s/\$//og;
		if ($price !~ /^\s*\d{1,6}\.\d{2}\s*$/o) {
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
	$xml = '';
}

print CN "\\.\n";
print CN "SELECT setval('asset.call_number_id_seq'::TEXT, $cn_id);\n";
print CP "\\.\n";
print CP "SELECT setval('asset.copy_id_seq'::TEXT, $cp_id);\n";

