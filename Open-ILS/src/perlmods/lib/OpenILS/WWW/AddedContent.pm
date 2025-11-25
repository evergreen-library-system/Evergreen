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
use OpenILS::Utils::CStoreEditor;

use LWP::UserAgent;
use MIME::Base64;

use Business::ISBN;
use Business::ISSN;

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

# Cache Types/Formats for clearing purposes
my %cachetypes = (
    jacket => ['small','medium','large'],
    toc => ['html','json','xml'],
    anotes => ['html','json','xml'],
    excerpt => ['html','json','xml'],
    reviews => ['html','json','xml'],
    summary => ['html','json','xml'],
);

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

    # If the URL requested matches a file on the filesystem, have Apache serve that file
    # this allows for local content (most typically images) to be used for some requests
    return Apache2::Const::DECLINED if (-e $r->filename);

    my $cgi = CGI->new;
    my @path_parts = split( /\//, $r->unparsed_uri );

    # Intended URL formats
    # /opac/extras/ac/jacket/medium/ISBN_VALUE      -- classic keyed-off-isbn
    # /opac/extras/ac/-3/-2/-1
    # /opac/extras/ac/jacket/medium/r/RECORD_ID     -- provide record id (bre.id)
    # /opac/extras/ac/-4/-3/-2/-1
    # /opac/extras/ac/jacket/medium/m/RECORD_ID     -- XXX: future use for metarecord id

    my $keytype_in_url = $path_parts[-2];  # if not in one of m, r, this will be the $format

    my $type;
    my $format;
    my $keytype;
    my $keyvalue;

    if ($keytype_in_url =~ m/^(r|m)$/) {
        $type = $path_parts[-4];
        $format = $path_parts[-3];
        $keyvalue = $path_parts[-1]; # a record/metarecord id
        $keytype = 'record';
    } else {
        $type = $path_parts[-3];
        $format = $path_parts[-2];
        $keyvalue = $path_parts[-1]; # an isbn
        $keytype = 'isbn';
    }

    my $res;
    my $keyhash;
    my $cachekey;

    $cachekey = ($keytype eq "isbn") ? $keyvalue : $keytype . '_' . $keyvalue;

    child_init() unless $handler;

    return Apache2::Const::NOT_FOUND unless $handler and $type and $format and $cachekey;

    if ($type eq "clearcache") {
        $r->no_cache(1); # Don't cache the clear cache info
        return $AC->clear_cache($format, $cachekey);
    }

    my $err;
    my $data;
    my $method = "${type}_${format}";

    return Apache2::Const::NOT_FOUND unless $handler->can($method);
    return $res if defined($res = $AC->serve_from_cache($type, $format, $cachekey));
    return Apache2::Const::NOT_FOUND unless $AC->lookups_enabled;

    if ($keytype eq "isbn") { # if this request uses isbn for the key
        # craft a hash with the single isbn, because that's all we will have
        $keyhash = {};
        $keyhash->{"isbn"} = [$keyvalue];
    } else {
        my $key_data = get_rec_keys($keyvalue);
        my @isbns = grep {$_->{tag} eq '020'} @$key_data;
        my @issns = grep {$_->{tag} eq '022'} @$key_data;
        my @upcs  = grep {$_->{tag} eq '024'} @$key_data;
        my @oclcs = grep {$_->{tag} eq '035'} @$key_data;

        map {
            # Attempt to validate the ISBN.
            # strip out hyphens;
            $_->{value} =~ s/-//g;
            #pull out the first chunk that looks like an ISBN:
            if ($_->{value} =~ /([0-9xX]{10}(?:[0-9xX]{3})?)/) {
                $_->{value} = $1;
                my $isbn_obj = Business::ISBN->new($_->{value});
                my $isbn_str;
                $isbn_str = $isbn_obj->as_string([]) if defined($isbn_obj);
                $_->{value} = $isbn_str;
            } else {
                undef $_->{value};
            }
            undef $_ if !defined($_->{value});
        } @isbns;

        map {
            my $issn_obj = Business::ISSN->new($_->{value});
            my $issn_str;
            $issn_str = $issn_obj->as_string() if defined($issn_obj && $issn_obj->is_valid);
            $_->{value} = $issn_str;
            undef $_ if !defined($_->{value});
        } @issns;

        # filter 035 fields for the values that look like OCLC numbers
        map {
            my $looks_like_oclc = $_->{value} =~ /(ocolc|ocm|ocl7|ocn)/i &&
                                  $_->{value} =~ /\d+/;
            if ($looks_like_oclc) {
                $_->{value} =~ s/\D+//g; # keep the number only;
                                         # the added content provider will be
                                         # responsible for any normalization it needs
            } else {
                undef $_;
            }
        } @oclcs;

        # Remove undef values from @isbns, @issns, and @oclcs.
        # Prevents empty requests to providers
        @isbns = grep {defined} @isbns;
        @issns = grep {defined} @issns;
        @oclcs = grep {defined} @oclcs;

        $keyhash = {
            isbn => [map {$_->{value}} @isbns],
            issn => [map {$_->{value}} @issns],
            upc  => [map {$_->{value}} @upcs],
            oclc => [map {$_->{value}} @oclcs]
        };
    }

    return Apache2::Const::NOT_FOUND unless @{$keyhash->{isbn}} || @{$keyhash->{issn}} || @{$keyhash->{upc}} || @{$keyhash->{oclc}};

    try {
        if ($handler->can('expects_keyhash') && $handler->expects_keyhash() eq 1) {
            # Handler expects a keyhash
            $data = $handler->$method($keyhash);
        } else {
            # Pass single ISBN as a scalar to the handler
            $data = $handler->$method($keyhash->{isbn}[0]);
        }
    } catch Error with {
        $err = shift;
        decr_error_countdown();
        $logger->debug("added content handler failed: $method($keytype/$keyvalue) => $err"); # XXX: logs unhelpful hashref
    };

    return Apache2::Const::NOT_FOUND if $err;

    if(!$data) {
        # if the AC lookup found no corresponding data, cache that information
        $logger->debug("added content handler returned no results $method($keytype/$keyvalue)") unless $data;
        $AC->cache_result($type, $format, $cachekey, {nocontent=>1});
        return Apache2::Const::NOT_FOUND;
    }
    
    $AC->print_content($data);
    $AC->cache_result($type, $format, $cachekey, $data);

    reset_error_countdown();
    return Apache2::Const::OK;
}

# returns [{tag => $tag, value => $value}, {tag => $tag2, value => $value2}]
sub get_rec_keys {
    my $id = shift;
    return OpenILS::Utils::CStoreEditor->new->json_query({
        select => {mfr => ['tag', 'value']},
        from => 'mfr',
        where => {
            record => $id,
            '-or' => [
                {
                    '-and' => [
                        {tag => '020'},
                        {subfield => 'a'}
                    ]
                }, {
                    '-and' => [
                        {tag => '022'},
                        {subfield => 'a'}
                    ]
                }, {
                    '-and' => [
                        {tag => '024'},
                        {subfield => 'a'},
                        {ind1 => 1}
                    ]
                }, {
                    '-and' => [
                        {tag => '035'},
                        {subfield => 'a'}
                    ]
                }
            ]
        },
        order_by => [
                { class => 'mfr', field => 'id' }
            ]
    });
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




# returns an HTTP::Response object
sub get_url {
    my( $self, $url ) = @_;

    $logger->info("added content getting [timeout=$net_timeout, errors_remaining=$error_countdown] URL = $url");
    my $agent = LWP::UserAgent->new(timeout => $net_timeout);

    my $res = $agent->get($url); 
    $logger->info("added content request returned with code " . $res->code);
    die "added content request failed: " . $res->status_line ."\n" unless $res->is_success;

    return $res;
}

# returns an HTTP::Response object
sub post_url {
    my( $self, $url, $content ) = @_;

    $logger->info("added content getting [timeout=$net_timeout, errors_remaining=$error_countdown] URL = $url");
    my $agent = LWP::UserAgent->new(timeout => $net_timeout);

    my $res = $agent->post($url, Content => $content);
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

sub delete_from_cache {
    my($class, $type, $format, $key) = @_;
    my $data = $cache->get_cache("ac.$type.$format.$key");
    if ($data) {
        $logger->debug("deleting $type/$format/$key from cache");
        $cache->delete_cache("ac.$type.$format.$key");
        return 1;
    }
    return 0;
}

sub clear_cache {
    my($class, $category, $key) = @_;
    my $data = {
        content_type => 'text/plain',
        content => "Checking/Clearing Cache Entries for $key\n"
    };
    my @cleartypes = ($category);
    if ($category eq 'all') {
        @cleartypes = keys(%cachetypes);
    }
    for my $type (@cleartypes) {
        for my $format (@{$cachetypes{$type}}) {
            if ($class->delete_from_cache($type, $format, $key)) {
                $data->{content} .= "Cleared $type/$format\n";
            }
        }
    }
    $data->{content} .= "Done Checking $key\n";
    return $class->print_content($data, 0);
}

1;
