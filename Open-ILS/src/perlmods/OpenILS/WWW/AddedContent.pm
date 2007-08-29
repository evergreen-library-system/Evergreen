package OpenILS::WWW::AddedContent;
use strict; use warnings;

use lib qw(/usr/lib/perl5/Bundle/);

use CGI;
use Apache2 ();
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use Data::Dumper;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;

use LWP::UserAgent;
use MIME::Base64;


# set the bootstrap config when this module is loaded
my $bs_config;
my $handler;

sub import {
    my $self = shift;
    $bs_config = shift;
}


my $net_timeout; # max seconds to wait for a response from the added content vendor
my $cache; # memcache handle
my $max_errors; # max consecutive lookup failures before added content is temporarily disabled
my $error_countdown; # current consecutive errors countdown
my $jacket_url; # URL for fetching jacket images

# number of seconds to wait before next lookup 
# is attempted after lookups have been disabled
my $error_retry_timeout;
my $init = 0; # has the child init been run?


sub child_init {

    OpenSRF::System->bootstrap_client( config_file => $bs_config );

    my $sclient = OpenSRF::Utils::SettingsClient->new();
    my $ac_data = $sclient->config_value("added_content");

    return unless $ac_data;

    $cache = OpenSRF::Utils::Cache->new;

    $net_timeout = $ac_data->{timeout} || 1;
    $error_countdown = $max_errors = $ac_data->{max_errors} || 10;
    $jacket_url = $ac_data->{jacket_url};
    $error_retry_timeout = $ac_data->{retry_timeout} || 600;

    $init = 1;
    
    my $ac_handler = $ac_data->{module};

    if($ac_handler) {
        $logger->debug("Attempting to load Added Content handler: $ac_handler");
    
        eval "use $ac_handler";
    
        if($@) {    
            $logger->error("Unable to load Added Content handler [$ac_handler]: $@"); 
            return; 
        }
    
        $handler = $ac_handler->new($ac_data);
        $logger->debug("added content loaded handler: $handler");
    }
}


sub handler {

    my $r   = shift;
    my $cgi = CGI->new;
    my $path = $r->path_info;

    my( undef, $data, $format, $key ) = split(/\//, $r->path_info);
    return Apache2::Const::NOT_FOUND unless $data and $format and $key;

    child_init() unless $init;
    return Apache2::Const::NOT_FOUND unless $init;

    return fetch_jacket($format, $key) if $data eq 'jacket';
    return Apache2::Const::NOT_FOUND unless lookups_enabled();

    my $err;
    my $success;
    my $method = "${data}_${format}";

    try {
        $success = $handler->$method($key);
    } catch Error with {
        my $err = shift;
        $logger->error("added content handler failed: $method($key) => $err");
        decr_error_countdown();
    };

    return Apache2::Const::NOT_FOUND if $err or !$success;
    return Apache2::Const::OK;
}

sub decr_error_countdown {
    $error_countdown--;
    if($error_countdown < 1) {
        $logger->warn("added content error count exhausted.  Disabling lookups for $error_retry_timeout seconds");
        disable_lookups();
    }
}

sub reset_error_countdown {
    $error_countdown = $max_errors;
}


# generic GET call
sub get_url {
    my( $self, $url ) = @_;
    $logger->info("added content getting [timeout=$net_timeout] URL = $url");
    my $agent = LWP::UserAgent->new(timeout => $net_timeout);
    my $res = $agent->get($url);
    die "added content request failed: " . $res->status_line ."\n" unless $res->is_success;
    reset_error_countdown();
    return $res->content;
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

sub fetch_jacket {
    my($size, $isbn) = @_;
    return Apache2::Const::NOT_FOUND unless $jacket_url and $size and $isbn;

    if($size eq 'small') {

        # try to serve small images from the cache first
        my $img_data = $cache->get_cache("ac.$size.$isbn");

        if($img_data) {

            $logger->debug("serving jacket $isbn from cache...");

            my $c_type = $img_data->{content_type};
            my $img = decode_base64($img_data->{img});

            print "Content-type: $c_type\n\n";

            binmode STDOUT;
            print $img;
            return Apache2::Const::OK;
        }
    }

    if(!lookups_enabled()) {
        $error_countdown = $max_errors; # reset the counter
        return Apache2::Const::NOT_FOUND;
    }

    (my $url = $jacket_url) =~ s/\${isbn}/$isbn/ig;

    $logger->debug("added content getting jacket with timeout=$net_timeout and URL = $url");

    my $res;
    my $err;

    try {
        my $agent = LWP::UserAgent->new(timeout => $net_timeout);
        $res = $agent->get($url);
    } catch Error with {
        $err = shift;
        $logger->error("added content lookup died with $err");
    };

    if( $err or $res->code == 500 ) {
        $logger->warn("added content jacket fetch failed (retries remaining = $error_countdown) " . 
            (($res) ? $res->status_line : "$err"));
        decr_error_countdown();
        return Apache2::Const::NOT_FOUND;
    }

    return Apache2::Const::NOT_FOUND unless $res->code == 200;

    # ignore old errors after a successful lookup
    reset_error_countdown();

    my $c_type = $res->header('Content-type');
    my $binary_img = $res->content;
    print "Content-type: $c_type\n\n";

    binmode STDOUT;
    print $binary_img;

    $cache->put_cache(
        "ac.$size.$isbn", {   
            content_type => $c_type, 
            img => encode_base64($binary_img,'')
        }
    ) if $size eq 'small';

    return Apache2::Const::OK;
}





1;

