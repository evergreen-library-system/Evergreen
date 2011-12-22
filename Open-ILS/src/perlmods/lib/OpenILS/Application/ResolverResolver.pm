#!/usr/bin/perl

# Copyright (C) 2009-2010 Dan Scott <dscott@laurentian.ca>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=head1 NAME

OpenILS::Application::ResolverResolver - retrieves holdings from OpenURL resolvers

=head1 SYNOPSIS

Via srfsh:
  request open-ils.resolver open-ils.resolver.resolve_holdings "issn", "0022-362X"
or:
  request open-ils.resolver open-ils.resolver.resolve_holdings.raw "issn", "0022-362X"

Via Perl:
  my $session = OpenSRF::AppSession->create("open-ils.resolver");
  my $request = $session->request("open-ils.resolver.resolve_holdings", [ "issn", "0022-362X" ] )->gather();
  $session->disconnect();

  # $request is a reference to the list of hashes

=head1 DESCRIPTION

OpenILS::Application::ResolverResolver caches responses from OpenURL resolvers
to requests for full-text holdings. Currently integration with SFX is supported.

Each org_unit can specify a different base URL as the third argument to
resolve_holdings(). Eventually org_units will have org_unit settings to hold
their resolver type and base URL.

=head1 AUTHOR

Dan Scott, dscott@laurentian.ca

=cut

package OpenILS::Application::ResolverResolver;

use strict;
use warnings;
use LWP::UserAgent;
use XML::LibXML;

# All OpenSRF applications must be based on OpenSRF::Application or
# a subclass thereof.  Makes sense, eh?
use OpenILS::Application;
use base qw/OpenILS::Application/;

# This is the client class, used for connecting to open-ils.storage
use OpenSRF::AppSession;

# This is an extension of Error.pm that supplies some error types to throw
use OpenSRF::EX qw(:try);

# This is a helper class for querying the OpenSRF Settings application ...
use OpenSRF::Utils::SettingsClient;

# ... and here we have the built in logging helper ...
use OpenSRF::Utils::Logger qw($logger);

# ... and this manages cached results for us ...
use OpenSRF::Utils::Cache;

# ... and this gives us access to the Fieldmapper
use OpenILS::Utils::Fieldmapper;

my $prefix = "open-ils.resolver_"; # Prefix for caching values
my $cache;
my $cache_timeout;
my $default_url_base;              # Default resolver location
my $resolver_type;              # Default resolver type
my $default_request_timeout;                    # Default browser timeout

our ($ua, $parser);


sub initialize {
    $cache = OpenSRF::Utils::Cache->new('global');
    my $sclient = OpenSRF::Utils::SettingsClient->new();
    $cache_timeout = $sclient->config_value(
        "apps", "open-ils.resolver", "app_settings", "cache_timeout" ) || 300;
    $default_url_base = $sclient->config_value(
        "apps", "open-ils.resolver", "app_settings", "default_url_base");
    $resolver_type = $sclient->config_value(
        "apps", "open-ils.resolver", "app_settings", "resolver_type") || 'sfx';
    # We set a browser timeout
    $default_request_timeout = $sclient->config_value(
        "apps", "open-ils.resolver", "app_settings", "request_timeout" ) || 60;
}

sub child_init {

    # We need a User Agent to speak to the SFX beast
    $ua = new LWP::UserAgent;
    $ua->agent('SameOrigin/1.0');

    # SFX returns XML to us; let us parse
    $parser = new XML::LibXML;
}

sub resolve_holdings {
    my $self = shift;
    my $conn = shift;
    my $id_type = shift;      # keep it simple for now, either 'issn' or 'isbn'
    my $id_value = shift;     # the normalized ISSN or ISBN
    my $url_base = shift || $default_url_base; 
    my $request_timeout = shift || $default_request_timeout; 

    if (!$id_type) {
        $logger->warn("Resolver was not given an ID type to resolve");
        return;
    }
    if (!$id_value) {
        $logger->warn("Resolver was not given an ID value to resolve");
        return;
    }

    # Need some sort of timeout in case resolver is unreachable
    $ua->timeout($request_timeout);

    if ($resolver_type eq 'cufts') {
        return cufts_holdings($self,$conn,$id_type,$id_value,$url_base);
    } else {
        return sfx_holdings($self,$conn,$id_type,$id_value,$url_base);
    }
}

sub cufts_holdings{

    my $self = $_[0];
    my $conn = $_[1];
    my $id_type = $_[2];
    my $id_value = $_[3];
    my $url_base = $_[4];

    # We'll use this in our cache key
    my $method = $self->api_name;

    # We might want to return raw JSON for speedier responses
    my $format = 'fieldmapper';
    if ($self->api_name =~ /raw$/) {
        $format = 'raw';
    }

    # Nice little CUFTS OpenURL request
    my $url_args = '?';

    if ($id_type eq 'issn') {
        $url_args .= "&issn=$id_value";
    } elsif ($id_type eq 'isbn') {
        $url_args .= "&isbn=$id_value";
    }
    
    my $ckey = $prefix . $method . $url_base . $id_type . $id_value; 

    # Check the cache to see if we've already looked this up
    # If we have, shortcut our return value
    my $result = $cache->get_cache($ckey) || undef;
    if ($result) {
        $logger->info("Resolver found a cache hit");    
        return $result;
    }

    my $res = undef;

    # Let's see what we we're trying to request
    $logger->info("Resolving the following request: $url_base$url_args");

    # We attempt to deal with potential problems in request
    eval {
        $res = $ua->get("$url_base$url_args"); 
    } or do {
        $logger->info("execution error");    
        return bow_out_gracefully("$url_base?ctx_ver=Z39.88-2004&rft.$id_type=$id_value",
            'Check link for additional holdings information.');
    };

    if ($res->status_line =~ /timeout/) {
        $logger->info("timeout error");    
        return bow_out_gracefully("$url_base?ctx_ver=Z39.88-2004&rft.$id_type=$id_value",
            'Check link for additional holdings information.');
    }

    my $xml = $res->content;
    my $parsed_cufts = $parser->parse_string($xml);

    my (@targets) = $parsed_cufts->findnodes('/CUFTS/resource/service[@name="journal"]');

    my @cufts_result;
    foreach my $target (@targets) {
        my %full_txt;

        # Ensure we have a name and especially URL to return
        $full_txt{'name'} = $target->findvalue('../@name[1]');
        $full_txt{'url'} = $target->findvalue('./result/url') || next;
        $full_txt{'coverage'} = $target->findvalue('./result/ft_start_date') . ' - ' . $target->findvalue('./result/ft_end_date');
        my $embargo = "";
        my $days_embargo = $target->findvalue('./result/embargo_days') || '';
        if (length($days_embargo) > 0) {
            $days_embargo = $days_embargo . " days ";
        }
        my $months_embargo = $target->findvalue('./result/embargo_months') || '';
        if (length($months_embargo) > 0) {
            $months_embargo = $months_embargo . " months ";
        }
        my $years_embargo = $target->findvalue('./result/embargo_years') || '';
        if (length($years_embargo) > 0) {
            $years_embargo = $years_embargo . " years ";
        }
        if (length($years_embargo . $months_embargo . $days_embargo) > 0) {
            $embargo = "(most recent " . $years_embargo . $months_embargo . $days_embargo . "unavailable due to publisher restrictions)";
        }
        $full_txt{'embargo'} = $embargo;

        if ($format eq 'raw') {
            push @cufts_result, {
                public_name => $full_txt{'name'},
                target_url => $full_txt{'url'},
                target_coverage => $full_txt{'coverage'},
                target_embargo => $full_txt{'embargo'},
            };
        } else {
            my $rhr = Fieldmapper::resolver::holdings_record->new;
            $rhr->public_name($full_txt{'name'});
            $rhr->target_url($full_txt{'url'});
            $rhr->target_coverage($full_txt{'coverage'});
            $rhr->target_embargo($full_txt{'embargo'});
            push @cufts_result, $rhr;
        }
    }

    # Stuff this into the cache
    $cache->put_cache($ckey, \@cufts_result, $cache_timeout);
    
    # Don't return the list unless it contains results
    if (scalar(@cufts_result)) {
        return \@cufts_result;
    }

    return undef;
}

sub sfx_holdings{

    my $self = $_[0];
    my $conn = $_[1];
    my $id_type = $_[2];
    my $id_value = $_[3];
    my $url_base = $_[4];

    # We'll use this in our cache key
    my $method = $self->api_name;

    # We might want to return raw JSON for speedier responses
    my $format = 'fieldmapper';
    if ($self->api_name =~ /raw$/) {
        $format = 'raw';
    }

    # Big ugly SFX OpenURL request
    my $url_args = '?url_ver=Z39.88-2004&url_ctx_fmt=infofi/fmt:kev:mtx:ctx&'
        . 'ctx_enc=UTF-8&ctx_ver=Z39.88-2004&rfr_id=info:sid/evergreen&'
        . 'sfx.ignore_date_threshold=1&'
        . 'sfx.response_type=multi_obj_detailed_xml&__service_type=getFullTxt';

    if ($id_type eq 'issn') {
        $url_args .= "&rft.issn=$id_value";
    } elsif ($id_type eq 'isbn') {
        $url_args .= "&rft.isbn=$id_value";
    }
    
    my $ckey = $prefix . $method . $url_base . $id_type . $id_value;

    # Check the cache to see if we've already looked this up
    # If we have, shortcut our return value
    my $result = $cache->get_cache($ckey) || undef;
    if ($result) {
        $logger->info("Resolver found a cache hit");    
        return $result;
    }

    my $res = undef;

    # Let's see what we we're trying to request
    $logger->info("Resolving the following request: $url_base$url_args");

    # We attempt to deal with potential problems in request
    eval {
        $res = $ua->get("$url_base$url_args"); 
    } or do {
        $logger->info("execution error");    
        return bow_out_gracefully("$url_base?ctx_ver=Z39.88-2004&rft.$id_type=$id_value",
            'Check link for additional holdings information.');
    };

    if ($res->status_line =~ /timeout/) {
        $logger->info("timeout error");    
        return bow_out_gracefully("$url_base?ctx_ver=Z39.88-2004&rft.$id_type=$id_value",
            'Check link for additional holdings information.');
    }

    # All clear
    my $xml = $res->content;
    my $parsed_sfx = $parser->parse_string($xml);

    my (@targets) = $parsed_sfx->findnodes('//target');

    my @sfx_result;
    foreach my $target (@targets) {
        my %full_txt;

        # Ensure we have a name and especially URL to return
        $full_txt{'name'} = $target->findvalue('./target_public_name') || next;
        $full_txt{'url'} = $target->findvalue('.//target_url') || next;
        $full_txt{'coverage'} = $target->findvalue('.//coverage_statement') || '';
        $full_txt{'embargo'} = $target->findvalue('.//embargo_statement') || '';

        if ($format eq 'raw') {
            push @sfx_result, {
                public_name => $full_txt{'name'},
                target_url => $full_txt{'url'},
                target_coverage => $full_txt{'coverage'},
                target_embargo => $full_txt{'embargo'},
            };
        } else {
            my $rhr = Fieldmapper::resolver::holdings_record->new;
            $rhr->public_name($full_txt{'name'});
            $rhr->target_url($full_txt{'url'});
            $rhr->target_coverage($full_txt{'coverage'});
            $rhr->target_embargo($full_txt{'embargo'});
            push @sfx_result, $rhr;
        }
    }

    # Stuff this into the cache
    $cache->put_cache($ckey, \@sfx_result, $cache_timeout);
    
    # Don't return the list unless it contains results
    if (scalar(@sfx_result)) {
        return \@sfx_result;
    }

    return undef;
}

# This uses the resolver structure for passing back a link directly to the resolver
sub bow_out_gracefully {
    my $alt_url = $_[0];
    my $reason = $_[1];

    my @sfx_result;
                
    push @sfx_result, {
        public_name => "Online holdings",
        target_url => $alt_url,
        target_coverage => $reason,
        target_embargo => "",
    };
   
    return \@sfx_result;
}

__PACKAGE__->register_method(
    method    => 'resolve_holdings',
    api_name  => 'open-ils.resolver.resolve_holdings',
    api_level => 1,
    argc      => 3,
    signature => {
        desc     => <<"         DESC",
Returns a list of "rhr" objects representing the full-text holdings for a given ISBN or ISSN
         DESC
        'params' => [ {
                name => 'id_type',
                desc => 'The type of identifier ("issn" or "isbn")',
                type => 'string' 
            }, {
                name => 'id_value',
                desc => 'The identifier value',
                type => 'string'
            }, {
                 name => 'url_base',
                 desc => 'The base URL for the resolver and instance',
                 type => 'string'
            }, {
                 name => 'request_timeout',
                 desc => 'The timeout for the HTTP request',
                 type => 'string'
            },
        ],
        'return' => {
            desc => 'Returns a list of "rhr" objects representing the full-text holdings for a given ISBN or ISSN',
            type => 'array'
        }
    }
);

__PACKAGE__->register_method(
    method    => 'resolve_holdings',
    api_name  => 'open-ils.resolver.resolve_holdings.raw',
    api_level => 1,
    argc      => 3,
    signature => {
        desc     => <<"         DESC",
Returns a list of raw JSON objects representing the full-text holdings for a given ISBN or ISSN
         DESC
        'params' => [ {
                name => 'id_type',
                desc => 'The type of identifier ("issn" or "isbn")',
                type => 'string' 
            }, {
                name => 'id_value',
                desc => 'The identifier value',
                type => 'string'
            }, {
                 name => 'url_base',
                 desc => 'The base URL for the resolver and instance',
                 type => 'string'
            }, {
                 name => 'request_timeout',
                 desc => 'The timeout for the HTTP request',
                 type => 'string'
            },
        ],
        'return' => {
            desc => 'Returns a list of raw JSON objects representing the full-text holdings for a given ISBN or ISSN',
            type => 'array'
        }
    }
);

# Clear cache for specific lookups
sub delete_cached_holdings {
    my $self = shift;
    my $conn = shift;
    my $id_type = shift;      # keep it simple for now, either 'issn' or 'isbn'
    my $id_value = shift;     # the normalized ISSN or ISBN
    my $url_base = shift || $default_url_base; 
    my @deleted_keys;

    $logger->warn("Deleting value [$id_value]");
    # We'll use this in our cache key
    foreach my $method ('open-ils.resolver.resolve_holdings.raw', 'open-ils.resolver.resolve_holdings') {
        my $ckey = $prefix . $method . $url_base . $id_type . $id_value;

        $logger->warn("Deleted cache key [$ckey]");
        my $result = $cache->delete_cache($ckey);

        $logger->warn("Result of deleting cache key: [$result]");
        push @deleted_keys, $result;
    }

    return \@deleted_keys;
}

__PACKAGE__->register_method(
    method    => 'delete_cached_holdings',
    api_name  => 'open-ils.resolver.delete_cached_holdings',
    api_level => 1,
    argc      => 3,
    signature => {
        desc     => <<"         DESC",
Deletes the cached value of the full-text holdings for a given ISBN or ISSN
         DESC
        'params' => [ {
                 name => 'url_base',
                 desc => 'The base URL for the resolver and instance',
                 type => 'string'
            }, {
                name => 'id_type',
                desc => 'The type of identifier ("issn" or "isbn")',
                type => 'string'
            }, {
                name => 'id_value',
                desc => 'The identifier value',
                type => 'string'
            }
        ],
        'return' => {
            desc => 'Deletes the cached value of the full-text holdings for a given ISBN or ISSN',
            type => 'array'
        }
    }
);


1;
