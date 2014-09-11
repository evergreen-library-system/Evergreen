#!/usr/bin/perl
use strict; use warnings;
use XML::LibXML;
use XML::LibXSLT;
my $out_file = 'IDL2js.js';
my $idl_file = '../../../../../../../examples/fm_IDL.xml';
my $xsl_file = '../../../../../../../xsl/fm_IDL2js.xsl'; 

my $xslt = XML::LibXSLT->new();
my $style_doc = XML::LibXML->load_xml(location => $xsl_file, no_cdata=>1);
my $stylesheet = $xslt->parse_stylesheet($style_doc);
my $idl_doc = XML::LibXML->load_xml(location => $idl_file);
my $results = $stylesheet->transform($idl_doc);
my $output = $stylesheet->output_as_bytes($results);

open(IDL, ">$out_file") or die "Cannot open IDL2js file $out_file : $!\n";

print IDL $output;

close(IDL);


