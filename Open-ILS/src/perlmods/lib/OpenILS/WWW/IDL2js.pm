package OpenILS::WWW::IDL2js;
use strict; use warnings;
use XML::LibXML;
use XML::LibXSLT;
use Apache2::Const -compile => qw(OK DECLINED HTTP_INTERNAL_SERVER_ERROR);
use Apache2::RequestRec;
use Apache2::SubRequest;
use Apache2::Filter;
use APR::Brigade;
use APR::Bucket;
use Error qw/:try/;
use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;
use CGI;

my $bs_config;
my $stylesheet;

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

    return Apache2::Const::OK;
}


my %idl_cache;
sub handler {
    my $r = shift;
    my $args = $r->args || '';
    child_init() unless $__initted;

    return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR unless $stylesheet;

    # pull the locale from the query string if present
    (my $locale = $args) =~ s/.*locale=([a-z]{2}-[A-Z]{2}).*/$1/g;

    # remove the locale argument from the query 
    # string, regardless of whether it was valid
    $args =~ s/([&;]?locale=[^&;]*)[&;]?//g; 

    # if no valid locale is present in the query 
    # string, pull it from the headers
    $locale = $r->headers_in->get('Accept-Language') unless $locale;

    if (!$locale or $locale !~ /^[a-z]{2}-[A-Z]{2}$/) {
        $r->log->debug("Invalid IDL2js locale '$locale'; using en-US");
        $locale = 'en-US';
    }

    $r->log->debug("IDL2js using locale '$locale'");

    my $output = '';
    my $stat = load_IDL($r, $locale, $args, \$output);
    return $stat unless $stat == Apache2::Const::OK;

    $r->content_type('application/x-javascript; encoding=utf8');
    $r->print($output);
    return Apache2::Const::OK;
}

# loads the IDL for the provided locale.
# when possible, use a cached version of the IDL.
sub load_IDL {
    my ($r, $locale, $args, $output_ref) = @_;

    # do we already have a cached copy of the IDL for this locale?
    if (!$args and $idl_cache{$locale}) {
        $$output_ref = $idl_cache{$locale};
        return Apache2::Const::OK;
    }

    # Fetch the locale-aware fm_IDL.xml via Apache subrequest.
    my $subr = $r->lookup_uri("/reports/fm_IDL.xml?locale=$locale");

    # filter allows us to capture the output of the subrequest locally
    # http://www.gossamer-threads.com/lists/modperl/modperl/97649#97649
    my $xml = ''; 
    $subr->add_output_filter(sub {
        my ($f, $bb) = @_; 
        while (my $e = $bb->first) { 
            $e->read(my $buf); 
            $xml .= $buf; 
            $e->delete; 
        } 
        return Apache2::Const::OK; 
    }); 

    $subr->run;

    if (!$xml) {
        $r->log->error("No IDL XML found");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    $xml =~ s/<!--.*?-->//sg;     # filter out XML comments ...
    $xml =~ s/(?:^|\s+)--.*$//mg; # and SQL comments ...
    $xml =~ s/^\s+/ /mg;          # and extra leading spaces ...
    $xml =~ s/\R*//g;             # and newlines

    my $output;
    try {
        my $idl_doc = XML::LibXML->load_xml(string => $xml);
        my $results = $stylesheet->transform($idl_doc, class_list => "'$args'");
        $output = $stylesheet->output_as_bytes($results);
    } catch Error with {
        my $e = shift;
        $r->log->error("IDL XSL Error: $e");
    };

    return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR unless $output;

    # only cache full versions of the IDL
    $idl_cache{$locale} = $output unless $args;

    # pass output back to the caller
    $$output_ref = $output;

    return Apache2::Const::OK; 
}

1;
