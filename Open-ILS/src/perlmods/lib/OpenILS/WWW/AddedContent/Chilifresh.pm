# ---------------------------------------------------------------
# Copyright (c) 2016  Equinox Open Library Initiative, Inc.
# Galen Charlton <gmc@equinoxOLI.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

package OpenILS::WWW::AddedContent::Chilifresh;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use OpenSRF::Utils::JSON;
use OpenSRF::EX qw/:try/;
use OpenILS::WWW::AddedContent;
use XML::LibXML;
use MIME::Base64;
use List::MoreUtils qw/uniq/;
use Digest::MD5 qw/md5_hex/;

my $AC = 'OpenILS::WWW::AddedContent';

sub new {
    my( $class, $args ) = @_;
    $class = ref $class || $class;
    return bless($args, $class);
}

sub chilifresh_generic {
    my $self = shift;
    return $self->{chilifresh_generic};
}

sub base_url {
    my $self = shift;
    return $self->{base_url};
}

sub expects_keyhash {
    # we expect a keyhash as opposed to a simple scalar containing an ISBN
    return 1;
}

# --------------------------------------------------------------------------
sub jacket_small {
    my( $self, $keys ) = @_;
    return $self->send_img(
        $self->fetch_direct_image('S', $keys));
}

sub jacket_medium {
    my( $self, $keys ) = @_;
    return $self->send_img(
        $self->fetch_direct_image('M', $keys));

}
sub jacket_large {
    my( $self, $keys ) = @_;
    return $self->send_img(
        $self->fetch_direct_image('L', $keys));
}

sub send_img {
    my($self, $response) = @_;
    my $image = $response->content;
    my $hash = md5_hex($image);
    if ($hash eq 'fc94fb0c3ed8a8f909dbc7630a0987ff') {
        # magic value for ChiliFresh's 1x1 placeholder
        return; # let it default to Evergreen's placeholder
    }
    return { 
        content_type => $response->header('Content-type'),
        content => $response->content, 
        binary => 1 
    };
}

# Construct a URL that should fetch a direct image, then
# grab it. The method name is called 'fetch_direct_image' because
# ChiliFresh offers a covers API that returns JSON or XML
# indicating whether an image actually exists, but it appears that
# it claims that an image exists regardless of whether or not it
# does. Consequently, we'll instead check to see whether a
# 1x1 placeholder is returned.
sub fetch_direct_image {
    my( $self, $size, $keys ) = @_;

    my @all_keys = uniq map
        { munge_keys($_, @{ $keys->{$_} }) }
        ('isbn', 'issn', 'upc', 'oclc');

    my $url = $self->base_url . '?isbn=' . join(',', @all_keys);
    $url .= '&size=' . $size;
    if (my $generic = $self->chilifresh_generic()) {
        $url .= '&generic=' . $generic;
    }
    $logger->debug('added_content: fetch ChiliFresh URL ' . $url);
    return $AC->get_url($url);
}

sub munge_keys {
    my $key_type = shift;
    my @keys = @_;

    return () if !@keys;

    if ($key_type eq 'oclc') {
        return map {
            # format the numeric OCLC number
            sprintf("(OCOLC)%-15.15d", $_);
        } @keys;
    } else {
        return @keys;
    }
}

1;
