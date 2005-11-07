#!/usr/bin/perl -w
use strict;
use XML::LibXML;
use Time::HiRes qw/time/;
use Getopt::Long;
use Data::Dumper;
use Error qw/:try/;
use open qw/:utf8/;

$|=1;

my ($userid,$sourceid,$rec_id,$entry_file,$id_tag) = (1,2,1,'marc_update.sql','//*[@tag="035"][1]');

GetOptions (	
	"sourceid"		=> \$sourceid,
	"sql_output=s"		=> \$entry_file,
	"userid=i"		=> \$userid,
	"first=i"		=> \$rec_id,
	"id_tag_xpath=s"	=> \$id_tag,
);

my $tcn_map;

open RE, ">$entry_file" or die "Can't open $entry_file!  $!\n";

print RE <<SQL;
BEGIN;
SQL

my $xact_id = time;

my $parser = XML::LibXML->new;

my $xml = '';
while ( $xml .= <STDIN> ) {
	chomp $xml;
	next unless $xml;

	my $tcn = '';
	my $success = 0;
	try {
		my $doc = $parser->parse_string($xml);;
		my @nodes = $doc->documentElement->findnodes( $id_tag );
		for my $n (@nodes) {
			$tcn .= $n->textContent;
		}
		$tcn =~ s/^\s*(\.+)\s*/$1/o;
		$tcn =~ s/\s+/_/go;
		$success = 1;
	} catch Error with {
		my $e = shift;
		warn $e;
		warn $xml;
	};	
	next unless $success;

	$xml =~ s/\t/\\t/go;
	$xml =~ s/'/''/go;

	$tcn =~ s/^.*?(\w+)\s*$/$1/go;
	
	unless ($tcn) {
		warn "\nNo TCN found for rec # $rec_id\n";
		$xml = '';
		$rec_id++;
		next;
	}

	if (exists($$tcn_map{$tcn})) {
		warn "\n !! TCN $tcn already exists!\n";
		$xml = '';
		next;
	}

	print ".";
	$$tcn_map{$tcn} = $rec_id;

	print RE "UPDATE biblio.record_entry SET marc = E'$xml' where id = $rec_id;\n";

	$rec_id++;
	$xml = '';
}


