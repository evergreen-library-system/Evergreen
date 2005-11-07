#!/usr/bin/perl -w
use strict;
use Error qw/:try/;
use MARC::Batch;
use MARC::File::XML;
use XML::LibXML;
use Getopt::Long;
use encoding 'utf8';

my ($out_enc, $in_enc, $filter) = ('UTF8','MARC8');
GetOptions('r=s' => \$filter, 'f=s' => \$in_enc, 't=s' => \$out_enc);
die("Please specify a filter with -r!\n") unless ($filter);

my $batch = MARC::Batch->new( 'USMARC', @ARGV );
$batch->strict_off;

my $parser = new XML::LibXML;

my $counter = 1;
my $current_file = $ARGV[0];

print STDERR "\nWorking on file $current_file ";

my $marc = $batch->next;
while ($marc) {

	my ($next,$xml,$doc,@nodes);

	try {
		$xml = $marc->as_xml();
	} otherwise {
		print STDERR "\n ARG! I couldn't parse the MARC record (number $counter): $@\n";
		$marc = $batch->next;
		$next++;
	};
	next if ($next);

	try {
		$doc = $parser->parse_string($xml);
	} otherwise {
		print STDERR "\n ARG! I couldn't turn the MARC record into MARCXML (number $counter): $@\n";
		$marc = $batch->next;
		$next++;
	};
	next if ($next);

	try {
		@nodes = $doc->documentElement->findnodes($filter);
	} otherwise {
		print STDERR "\n ARG! I couldn't prune the MARCXML record (number $counter): $@\n";
		$marc = $batch->next;
		$next++;
	};
	next if ($next);

	for my $n (@nodes) {
		$n->parentNode->removeChild($n);
	}

	my $string = $doc->toStringC14N;
	$string =~ s/\n/ /gso;
	$string =~ s/\t/ /gso;
	$string =~ s/>\s+</></gso;

	print "$string\n";
	
	unless ($counter % 1000) {
		if ($current_file ne $batch->filename) {
			$current_file = $batch->filename;
			print STDERR "\nWorking on file $current_file ";
		}
		print STDERR '.'
	}
	$counter++;
	try {
		$marc = $batch->next;
	} otherwise {
		print STDERR "\n ARG! I couldn't parse the MARC record (number $counter): $@\n";
		$marc = $batch->next;
	}
}
