package OpenILS::WWW::EGWeb::CGI_utf8;

# The code in this module is copied from (except for a tiny modification)
# Template::Plugin::CGI, which is written by:
#
# Andy Wardley E<lt>abw@wardley.orgE<gt> L<http://wardley.org/>
#
# Copyright (C) 1996-2007 Andy Wardley.  All Rights Reserved.
#
# This module is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

use strict;
use warnings;
use base 'Template::Plugin';
use CGI qw(:all -utf8 -oldstyle_urls);

sub new {
    my $class   = shift;
    my $context = shift;
    new CGI(@_);
}

# monkeypatch CGI::params() method to Do The Right Thing in TT land

sub CGI::params {
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

1;
