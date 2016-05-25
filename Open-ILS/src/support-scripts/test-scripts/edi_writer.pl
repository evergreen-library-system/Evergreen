#!/usr/bin/perl
use strict; use warnings;
use OpenILS::Utils::EDIWriter;
require '../oils_header.pl';
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use Getopt::Long;

my $config = '/openils/conf/opensrf_core.xml';
my $po_id;

GetOptions(
    'osrf-config' => \$config,
    'po-id=i' => \$po_id
);


osrf_connect($config);

my $writer = OpenILS::Utils::EDIWriter->new({pretty => 1});
#my $writer = OpenILS::Utils::EDIWriter->new;
my $edi = $writer->write($po_id);

print "$edi\n";


