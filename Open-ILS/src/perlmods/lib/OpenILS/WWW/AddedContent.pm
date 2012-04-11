package OpenILS::WWW::AddedContent;
use strict; use warnings;

use CGI;
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use Data::Dumper;
use UNIVERSAL::require;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;

use LWP::UserAgent;
use MIME::Base64;

my $AC = __PACKAGE__;


# set the bootstrap config when this module is loaded
my $bs_config;

sub import {
    my $self = shift;
    $bs_config = shift;
}


my $handler; # added content handler class handle
my $cache; # memcache handle
my $net_timeout; # max seconds to wait for a response from the added content vendor
my $max_errors; # max consecutive lookup failures before added content is temporarily disabled
my $error_countdown; # current consecutive errors countdown

# number of seconds to wait before next lookup 
# is attempted after lookups have been disabled
my $error_retry_timeout;


sub child_init {

    OpenSRF::System->bootstrap_client( config_file => $bs_config );
    $cache = OpenSRF::Utils::Cache->new;

    my $sclient = OpenSRF::Utils::SettingsClient->new();
    my $ac_data = $sclient->config_value("added_content");

    return Apache2::Const::OK unless $ac_data;
    my $ac_handler = $ac_data->{module};
    return Apache2::Const::OK unless $ac_handler;

    $net_timeout = $ac_data->{timeout} || 1;
    $error_countdown = $max_errors = $ac_data->{max_errors} || 10;
    $error_retry_timeout = $ac_data->{retry_timeout} || 600;

    $logger->debug("Attempting to load Added Content handler: $ac_handler");

    $ac_handler->use;

    if($@) {    
        $logger->error("Unable to load Added Content handler [$ac_handler]: $@"); 
        return Apache2::Const::OK; 
    }

    $handler = $ac_handler->new($ac_data);
    $logger->debug("added content loaded handler: $handler");
    return Apache2::Const::OK;
}


sub handler {

    my $r   = shift;
    return Apache2::Const::DECLINED if (-e $r->filename);

    my $cgi = CGI->new;
    my @path_parts = split( /\//, $r->unparsed_uri );
    my $type = $path_parts[-3];
    my $format = $path_parts[-2];
    my $key = $path_parts[-1];
    my $res;

    child_init() unless $handler;

    return Apache2::Const::NOT_FOUND unless $handler and $type and $format and $key;

    my $err;
    my $data;
    my $method = "${type}_${format}";

    return Apache2::Const::NOT_FOUND unless $handler->can($method);
    return $res if defined($res = $AC->serve_from_cache($type, $format, $key));
    return Apache2::Const::NOT_FOUND unless $AC->lookups_enabled;

    try {
        $data = $handler->$method($key);
    } catch Error with { 
        $err = shift; 
        decr_error_countdown();
        $logger->debug("added content handler failed: $method($key) => $err");
    };

    return Apache2::Const::NOT_FOUND if $err;

    if(!$data) {
        # if the AC lookup found no corresponding data, cache that information
        $logger->debug("added content handler returned no results $method($key)") unless $data;
        $AC->cache_result($type, $format, $key, {nocontent=>1});
        return Apache2::Const::NOT_FOUND;
    }
    
    $AC->print_content($data);
    $AC->cache_result($type, $format, $key, $data);

    reset_error_countdown();
    return Apache2::Const::OK;
}

sub print_content {
    my($class, $data, $from_cache) = @_;
    return Apache2::Const::NOT_FOUND if $data->{nocontent};

    my $ct = $data->{content_type};
    my $content = $data->{content};
    print "Content-type: $ct\n\n";

    if($data->{binary}) {
        binmode STDOUT;
        # if it hasn't been cached yet, it's still in binary form
        print( ($from_cache) ? decode_base64($content) : $content );
    } else {
        print $content;
    }


    return Apache2::Const::OK;
}




# returns an HTPP::Response object
sub get_url {
    my( $self, $url ) = @_;

    $logger->info("added content getting [timeout=$net_timeout, errors_remaining=$error_countdown] URL = $url");
    my $agent = LWP::UserAgent->new(timeout => $net_timeout);

    my $res = $agent->get($url); 
    $logger->info("added content request returned with code " . $res->code);
    die "added content request failed: " . $res->status_line ."\n" unless $res->is_success;

    return $res;
}

sub lookups_enabled {
    if( $cache->get_cache('ac.no_lookup') ) {
        $logger->info("added content lookup disabled");
        return undef;
    }
    return 1;
}

sub disable_lookups {
    $cache->put_cache('ac.no_lookup', 1, $error_retry_timeout);
}

sub decr_error_countdown {
    $error_countdown--;
    if($error_countdown < 1) {
        $logger->warn("added content error count exhausted.  Disabling lookups for $error_retry_timeout seconds");
        $AC->disable_lookups;
    }
}

sub reset_error_countdown {
    $error_countdown = $max_errors;
}

sub cache_result {
    my($class, $type, $format, $key, $data) = @_;
    $logger->debug("caching $type/$format/$key");
    $data->{content} = encode_base64($data->{content}) if $data->{binary};
    return $cache->put_cache("ac.$type.$format.$key", $data);
}

sub serve_from_cache {
    my($class, $type, $format, $key) = @_;
    my $data = $cache->get_cache("ac.$type.$format.$key");
    return undef unless $data;
    $logger->debug("serving $type/$format/$key from cache");
    return $class->print_content($data, 1);
}



1;
