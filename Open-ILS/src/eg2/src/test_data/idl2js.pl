#!/usr/bin/perl
use strict; use warnings;
use XML::LibXML;
use XML::LibXSLT;
my $out_file = 'IDL2js.js';
my $idl_file = '../../../../examples/fm_IDL.xml';
my $xsl_file = '../../../../xsl/fm_IDL2js.xsl'; 

my $xslt = XML::LibXSLT->new();
my $style_doc = XML::LibXML->load_xml(location => $xsl_file, no_cdata=>1);
my $stylesheet = $xslt->parse_stylesheet($style_doc);
my $idl_string = preprocess_idl_file($idl_file);
my $idl_doc = XML::LibXML->load_xml(string => $idl_string);
my $results = $stylesheet->transform($idl_doc);
my $output = $stylesheet->output_as_bytes($results);

open(IDL, ">$out_file") or die "Cannot open IDL2js file $out_file : $!\n";

print IDL $output;

close(IDL);


sub preprocess_idl_file {
       my $file = shift;
       open my $idl_fh, '<', $file or die "Unable to open IDL file $file : $!\n";
       local $/ = undef;
       my $xml = <$idl_fh>;
       close($idl_fh);
       # These substitutions are taken from OpenILS::WWW::IDL2js
       $xml =~ s/<!--.*?-->//sg;     # filter out XML comments ...
       $xml =~ s/(?:^|\s+)--.*$//mg; # and SQL comments ...
       $xml =~ s/^\s+/ /mg;          # and extra leading spaces ...
       $xml =~ s/\R*//g;             # and newlines
       return $xml;
}
