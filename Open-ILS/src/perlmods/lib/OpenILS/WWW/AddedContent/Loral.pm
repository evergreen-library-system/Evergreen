# ---------------------------------------------------------------
# Copyright (c) 2026 North of Boston Library Exchange, Inc.
# Jason Stephenson <jason@sigio.com>
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

package OpenILS::WWW::AddedContent::Loral;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use OpenILS::WWW::AddedContent;
use MIME::Base64;

my $AC = 'OpenILS::WWW::AddedContent';

sub new {
    my( $class, $args ) = @_;
    $class = ref $class || $class;
    return bless($args, $class);
}

sub base_url {
    my $self = shift;
    return $self->{base_url};
}

sub authorization {
    my $self = shift;
    my $value = "Basic " . encode_base64($self->{Loral}->{userid} . ":" . $self->{Loral}->{password});
    return ('Authorization', $value);
}

# Loral uses ISBN or UPC.
sub expects_keyhash {
    return 1;
}

# Cover images:
sub jacket_small {
    my ($self, $keys) = @_;
    return $self->send_img(
        $self->fetch_cover('small', $keys)
    );
}

sub jacket_medium {
    my ($self, $keys) = @_;
    return $self->send_img(
        $self->fetch_cover('medium', $keys)
    );
}

sub jacket_large {
    my ($self, $keys) = @_;
    return $self->send_img(
        $self->fetch_cover('large', $keys)
    );
}

sub anotes_html {
    my ($self, $keys) = @_;
    my $content = $self->fetch_content('AuthorBio', $keys);
    if ($content->{success}) {
        return $self->send_html($content->{biography});
    }
    return 0;
}

sub summary_html {
    my ($self, $keys) = @_;
    my $content = $self->fetch_content('Description', $keys);
    if ($content->{success}) {
        return $self->send_html($content->{description});
    }
    return 0;
}

sub reviews_html {
    my ($self, $keys) = @_;
    my $content = $self->fetch_content('Reviews', $keys);
    if ($content->{success} && ref($content->{reviews}) eq 'HASH') {
        my $html = '<ul>';
        foreach my $key (keys %{$content->{reviews}}) {
            my $review = $content->{reviews}->{$key};
            $html .= '<li>';
            $html .= '<b>' . $review->{Source} . '</b><br>' if ($review->{Source});
            # Junk at the beginning of some reviews.
            $review->{Content} =~ s/^\*"//g;
            # Some reviews contain HTML that will break the layout.
            if ($review->{Content} =~ /<p>/) {
                $review->{Content} =~ s@</p><p>@<br>@g;
                $review->{Content} =~ s@</?p>@@g;
            }
            $html .= $review->{Content} . '</li>'
        }
        $html .= '</ul>';
        return $self->send_html($html);
    }
    return 0;
}

sub reviews_json {
    my ($self, $keys) = @_;
    my $content = $self->fetch_content('Reviews', $keys);
    if ($content->{success} && ref($content->{reviews}) eq 'HASH') {
        return $self->send_json($content->{reviews});
    }
    return 0;
}

sub fetch_cover {
    my ($self, $size, $keys) = @_;
    my $key = _get_key($keys);
    my $url = sprintf("%s/Enrichment/Cover?isn=%s\&size=%s", $self->base_url,
                      $key, $size);
    my @headers = $self->authorization;
    return $AC->get_url($url, \@headers);
}

sub fetch_content {
    my ($self, $option, $keys) = @_;
    my $key = _get_key($keys);
    my $url = sprintf("%s/Enrichment/%s?isn=%s", $self->base_url, $option, $key);
    my @headers = $self->authorization;
    my $response = $AC->get_url($url, \@headers);
    return OpenSRF::Utils::JSON->JSON2perl($response->content);
}

sub send_img {
    my ($self, $response) = @_;
    return {
        content_type => $response->header('Content-type'),
        content => $response->content,
        binary => 1
    };
}

sub send_html {
    my ($self, $content) = @_;

    my $HTML = <<"    HTML";
        <div>
            <style type='text/css'>
                div.ac input, div.ac a[href],div.ac img, div.ac button { display: none; visibility: hidden }
            </style>
            <div class='ac'>
                $content
            </div>
        </div>
    HTML

    return {content_type=>'text/html', content => $HTML};
}

sub send_json {
    my ($self, $content) = @_;
    return {content_type => "text/plan",
            content => OpenSRF::Utils::JSON->perl2JSON($content)};
}

# Helper function to get first ISBN or UPC.
sub _get_key {
    my $keyhash = shift;
    if (@{$keyhash->{isbn}}) {
        return $keyhash->{isbn}->[0];
    } elsif (@{$keyhash->{upc}}) {
        return $keyhash->{upc}->[0];
    }
    return undef;
}

1;
