#
# OpenILS::Template::Plugin::ResolverResolver
#
# DESCRIPTION
#
#   Simple Template Toolkit Plugin which hooks into Dan Scott's Resolver
#
# AUTHOR
#   Art Rhyno <http://projectconifer.ca>
#
# COPYRIGHT
#   Copyright (C) 2011
#
# LICENSE
# GNU General Public License v2 or later
#
#============================================================================

package Template::Plugin::ResolverResolver;

use strict;
use warnings;
use base 'Template::Plugin';
use OpenILS::Application::ResolverResolver;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenSRF::AppSession;


our $VERSION = 0.9;

sub load {
    my ( $class, $context ) = @_;
    return $class;
}   

sub new { 
    my ( $class, $context, @params ) = @_;

    bless { _CONTEXT => $context, }, $class;   
} 

# monkeypatch ResolverResolver::params() method to Do The Right Thing in TT land

sub ResolverResolver::params {
    my $self = shift;
    local $" = ', ';

    return $self->{ _TT_PARAMS } ||= do {
        # must call Vars() in a list context to receive
        # plain list of key/vals rather than a tied hash
        my $params = { $self->Vars() };

        # convert any null separated values into lists
        @$params{ keys %$params } = map { 
            /\0/ ? [ split /\0/ ] : $_ 
        } values %$params;

        $params;
    };
}

sub resolve_issn
{
    my ($class, $issn, $baseurl, $timeout) = @_;

    if (length($issn) <= 9) {
           my $session = OpenSRF::AppSession->create("open-ils.resolver");
    
           my $request = $session->request("open-ils.resolver.resolve_holdings.raw", "issn", $issn, $baseurl, $timeout)->gather();
           if ($request) {
                 return $request;
           }
           $session->disconnect();
    }
        
    return "";
}

sub resolve_isbn
{
    my ($class, $isbn, $baseurl, $timeout) = @_;

    my $session = OpenSRF::AppSession->create("open-ils.resolver");
    
    my $request = $session->request("open-ils.resolver.resolve_holdings.raw", "isbn", $isbn, $baseurl, $timeout)->gather();
    
    if ($request) {
            return $request;
    }
    $session->disconnect();
        
    return "";
}


1;

