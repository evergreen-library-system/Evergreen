# ---------------------------------------------------------------
# Copyright (C) 2016 Jakub Kotrla <jakub@kotrla.net>
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

package OpenILS::WWW::AddedContent::ObalkyKnih;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use OpenILS::WWW::AddedContent;
use OpenSRF::Utils::JSON;
use OpenSRF::EX qw/:try/;
use HTML::Entities;
use Date::Parse;
use POSIX qw(strftime);

# Edit the <added_content> section of /openils/conf/opensrf.xml
# Change <module> to:
#   <module>OpenILS::WWW::AddedContent::ObalkyKnih</module>
# 
# That will provide cover, summary, ToC (PDF, text), rating and reviews from
# provider obalkyknih.cz.
# You can swich off some features by adding following settings to <added_content>:
# <ObalkyKnih>
# <!-- Covers are there always -->
#   <!-- Annotations provided by obalkyknih.cz is mapped to evergreen summary -->
#   <summary>true</summary>
#   <!-- Provider obalkyknih.cz provides TOC as text and as PDF plus thumbnail -->
#   <tocPdf>true</tocPdf>
#   <tocText>true</tocText>
#   <!-- User reviews from obalkyknih.cz -->
#   <reviews>true</reviews>
# </ObalkyKnih>

my $AC = 'OpenILS::WWW::AddedContent';

# This should work for most setups
my $blank_img = 'http://localhost/opac/images/blank.png';

# This URL is always the same for obalkyknih.cz, so there's no advantage to
# pulling from opensrf.xml
my $api_url = 'http://cache.obalkyknih.cz/api/';


sub new {
    my( $class, $args ) = @_;
    $class = ref $class || $class;
    return bless($args, $class);
}


# --------------------------------------------------------------------------
sub expects_keyhash {
    # we expect a keyhash as opposed to a simple scalar containing an ISBN
    return 1;
}

# --------------------------------------------------------------------------
sub jacket_small {
    my( $self, $keys ) = @_;
    return $self->send_img(
        $self->fetch_cover_response('cover_icon_url', $keys));
}

sub jacket_medium {
    my( $self, $keys ) = @_;
    return $self->send_img(
        $self->fetch_cover_response('cover_medium_url', $keys));

}
sub jacket_large {
    my( $self, $keys ) = @_;
    return $self->send_img(
        $self->fetch_cover_response('cover_preview510_url', $keys));
}

# --------------------------------------------------------------------------


# annotations provided by obalkyknih.cz is mapped to evergreen summary
sub summary_html {
    my( $self, $keys ) = @_;
    my $key = $self->select_key($keys);

    if ($self->{ObalkyKnih}->{summary} eq "false") { return 0; }

    my $book_data = $self->fetch_response_obalky($key);
    my $annotation = $book_data->{'annotation'};

    if (!$annotation) {
        $logger->debug("ObalkyKnih.cz no summary for $key");
        return 0;
    }

    my $annot_source = $annotation->{'source'};
    my $annot_text = $annotation->{'html'};

    my $annot_html .= "<div style='margin:10px' title='Zdroj: $annot_source'>$annot_text</div>\n";

    $self->send_html($annot_html);
}


# obalkyknih.cz provides TOC as text and as PDF plus thumbnail
sub toc_html {
    my( $self, $keys ) = @_;
    my $key = $self->select_key($keys);

    if ($self->{ObalkyKnih}->{tocPdf} eq "false" && $self->{ObalkyKnih}->{tocText} eq "false") { return 0; }

    my $book_data = $self->fetch_response_obalky($key);

    my $toc_text = $book_data->{toc_full_text};
    my $toc_pdf_url = $book_data->{toc_pdf_url};
    my $toc_thumbnail_url = $book_data->{toc_thumbnail_url};

    my $toc_html;
    if ($self->{ObalkyKnih}->{tocPdf} ne "false" && $toc_pdf_url && $toc_thumbnail_url) {
        $toc_html .= "<div style='margin:10px'>";
        $toc_html .= "<a href='$toc_pdf_url'><img src='$toc_thumbnail_url' alt='TOC $key' /></a>";
        $toc_html .= "</div>";
    }
    if ($self->{ObalkyKnih}->{tocText} ne "false" && $toc_text) {
        $toc_html .= "<div style='margin:10px'><pre>$toc_text</pre></div>";
    }

    my $toc_html_length = length $toc_html;

    # No table of contents is available for this book; short-circuit
    if ($toc_html_length < 1) {
        $logger->debug("ObalkyKnih.cz no TOC for $key");
        return 0;
    }

    $self->send_html($toc_html);
}

# user reviews from obalkyknih.cz
sub reviews_html {
    my( $self, $keys ) = @_;
    my $key = $self->select_key($keys);

    if ($self->{ObalkyKnih}->{reviews} eq "false") { return 0; }

    my $book_data = $self->fetch_response_obalky($key);
    my $reviews = $book_data->{'reviews'};

    if (!$reviews) {
        $logger->debug("ObalkyKnih.cz no reviews for $key");
        return 0;
    }

    my $reviews_html = "";
    foreach my $review (@$reviews) {
        my $created = $review->{created};
        my $html_text = $review->{html_text};
        my $library_name = $review->{library_name};

        my @createdParsed = gmtime(str2time($created));
        $created = POSIX::strftime("%-d. %-m. %Y\n", @createdParsed);

        $reviews_html .= "<div style='margin-top:10px'>" .
            "<div>$html_text</div>" .
            "<div style='font-style: italic'>Zdroj: $library_name, $created</div>" .
            "</div>\n";
    }

    my $rating_count = $book_data->{'rating_count'};
    my $rating_avg100 = $book_data->{'rating_avg100'};
    my $rating_url = $book_data->{'rating_url'};

    my $rating_html = "";
    if ($rating_count > 0) {
        $rating_html = " $rating_avg100 %<br /><img src='$rating_url' /><br /> Hodnoceno: ${rating_count}x";   
    }

    my $rr_html_length = length($reviews_html . $rating_html);
    if ($rr_html_length < 1) {
        $logger->debug("ObalkyKnih.cz no reviews for $key");
        return 0;
    }

    $self->send_html("$rating_html <div style='margin:20px' class='reviews'>$reviews_html</div>");
}

# --------------------------------------------------------------------------

sub send_img {
    my($self, $response) = @_;
    return { 
        content_type => $response->header('Content-type'),
        content => $response->content, 
        binary => 1 
    };
}

sub send_html {
    my( $self, $content ) = @_;
    return 0 unless $content;

    # evergreen has encoding issues, so change non-ASCII chars to HTML entity
    $content = encode_entities($content, '^\x00-\x7F');

    return { content_type => 'text/html; charset=utf-8', content => $content };
}

# --------------------------------------------------------------------------

# returns the HTTP response object from the URL fetch
sub fetch_response_obalky {
    my( $self, $key ) = @_;

    # obalkyknih.cz can also accept nbn, oclc
    # Hardcoded to only accept ISBNs in format API_URL/books?isbn=9788086964096
    $key = "books?isbn=$key";

    my $url = $api_url . $key;
    my $response = $AC->get_url($url)->decoded_content((charset => 'UTF-8'));

    $logger->debug("ObalkyKnih.cz for $key response was $response");

    my $book_results = OpenSRF::Utils::JSON->JSON2perl($response);
    my $record = $book_results->[0];

    # We didn't find a matching book; short-circuit our response
    if (!$record) {
        $logger->debug("ObalkyKnih.cz for $key no record found");
        return 0;
    }

    return $record;
}


# returns a cover image from the list of associated items
sub fetch_cover_response {
    my( $self, $size, $keys ) = @_;

    my $key = $self->select_key($keys);
    my $response = $self->fetch_response_obalky($key);

    # Short-circuit if we get an empty response, or a response
    # with no matching records
    if (!$response or scalar(keys %$response) == 0) {
        $logger->debug("ObalkyKnih.cz for $key no cover url for this book");
        return $AC->get_url($blank_img);
    }

    # Try to return a cover image from the record->data metadata
    my $cover = $response->{$size};

    if ($cover) {
        return $AC->get_url($cover);
    }

    $logger->debug("ObalkyKnih.cz for $key no covers for this book");

    # Return a blank image
    return $AC->get_url($blank_img);
}


# return key, i.e. nvl(ISBN, ISSN)
sub select_key {
    my ($self, $keys) = @_;

    my $isbn = $keys->{isbn}[0];
    # not used now : my $upc  = $keys->{upc}[0];
    my $issn = $keys->{issn}[0];
 
    my $key;
    if (defined($isbn)) {
        $key = $isbn;
    }
    if (defined($issn)) {
        $key = $issn;
    }

    return $key;
}


1;
