package OpenILS::WWW::IDL2js;
use strict; use warnings;
use XML::LibXML;
use XML::LibXSLT;
use Apache2::Const -compile => qw(OK DECLINED HTTP_INTERNAL_SERVER_ERROR);
use Error qw/:try/;
use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;

my $bs_config;
my $stylesheet;
my $idl_doc;


# load and parse the stylesheet
sub import {
    my $self = shift;
    $bs_config = shift;
}

# parse the IDL, loaded from the network
my $__initted = 0;
sub child_init {
    $__initted = 1;

    OpenSRF::System->bootstrap_client(config_file => $bs_config);
    my $sclient = OpenSRF::Utils::SettingsClient->new();

    my $xsl_file = $sclient->config_value('IDL2js');

    unless($xsl_file) {
        warn "XSL2js XSL file required for IDL2js Apache module\n";
        return;
    }

    $xsl_file = $sclient->config_value(dirs => 'xsl')."/$xsl_file";
    my $idl_file = $sclient->config_value("IDL");

    my $xslt = XML::LibXSLT->new();

    try {

        my $style_doc = XML::LibXML->load_xml(location => $xsl_file, no_cdata=>1);
        $stylesheet = $xslt->parse_stylesheet($style_doc);

    } catch Error with {
        my $e = shift;
        warn "Invalid XSL File: $xsl_file: $e\n";
    };

    $idl_doc = XML::LibXML->load_xml(location => $idl_file);
    return Apache2::Const::OK;
}


sub handler {
    my $r = shift;
    my $args = $r->args || '';
    child_init() unless $__initted;

    return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR unless $stylesheet and $idl_doc;
    return Apache2::Const::DECLINED if $args and $args !~ /^[a-zA-Z,]*$/;

    my $output;
    try {
        my $results = $stylesheet->transform($idl_doc, class_list => "'$args'");
        $output = $stylesheet->output_as_bytes($results);
    } catch Error with {
        my $e = shift;
        $r->log->error("IDL XSL Error: $e");
    };

    return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR unless $output;

    $r->content_type('application/x-javascript; encoding=utf8');
    $r->print($output);
    return Apache2::Const::OK;
}

1;
