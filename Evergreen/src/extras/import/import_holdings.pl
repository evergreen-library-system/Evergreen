#!/usr/bin/perl -w
use strict;
use XML::LibXML;
use Time::HiRes qw/time/;
use Getopt::Long;
use Data::Dumper;
use Error qw/:try/;
use open qw/:utf8/;

$|=1;

my ($userid, $sourceid, $cn_id, $cp_id, $cp_file, $cn_file, $map_file, $lib_map_file) =
	(1, 2, 1, 1, 'asset_copy.sql','asset_volume.sql','record_id_map.pl','lib-map.pl');

GetOptions (	
	"sourceid"		=> \$sourceid,
	"copy_file=s"		=> \$cp_file,
	"volume_file=s"		=> \$cn_file,
	"tcn_map_file=s"	=> \$map_file,
	"lib_map_file=s"	=> \$lib_map_file,
	"userid=i"		=> \$userid,
	"first_volume=i"	=> \$cn_id,
	"first_copy=i"		=> \$cp_id,
);

my $tcn_map;
my $lib_map;

eval `cat $map_file`;
eval `cat $lib_map_file`;

open CP, ">$cp_file" or die "Can't open $cp_file!  $!\n";
open CN, ">$cn_file" or die "Can't open $cn_file!  $!\n";


print CP <<SQL;
SET CLIENT_ENCODING TO 'UNICODE';
COPY asset.copy (id,editor,creator,barcode,call_number,copy_number,available,loan_duration,fine_level,circulate,deposit,deposit_amount,price,ref,opac_visible) FROM STDIN;
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

	for my $node ($doc->documentElement->findnodes('/*/*[@tag="999"]')) {
		my $barcode = $node->findvalue( '*[@code="i"]' );
		my $label = $node->findvalue( '*[@code="a"]' );
		my $owning_lib = $$lib_map{ $node->findvalue( '*[@code="m"]' ) };
		my $price = $node->findvalue( '*[@code="p"]' );
		my $copy_number = $node->findvalue( '*[@code="c"]' );
		my $available = $node->findvalue( '*[@code="k"]' ) ? 1 : 0;

		next unless $barcode;
		next unless $owning_lib;
		next unless $label;

		$barcode =~ s/\\/\\\\/og;
		$label =~ s/\\/\\\\/og;
		$price =~ s/\$//og;
		$price ||= '0.00';

		unless (exists($$cn_map{"$rec_id/$owning_lib/$label"})) {
			$$cn_map{"$rec_id/$owning_lib/$label"} = $cn_id;
			print CN join("\t",($cn_id,$userid,$userid,$rec_id,$label,$owning_lib))."\n";
			print 'v';
			$cn_id++;
		}

# id,editor,creator,barcode,call_number,copy_number,available,loan_duration,fine_level,circulate,deposit,deposit_amount,price,ref,opac_visible

		print CP join("\t", (	$cp_id,$userid,$userid,$barcode,
					$$cn_map{"$rec_id/$owning_lib/$label"},
					$copy_number,$available,2,2,1,0,'0.00',
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

