# ---------------------------------------------------------------
# Copyright (C) 2009 David Christensen <david.a.christensen@gmail.com>
# Copyright (C) 2009-2011 Dan Scott <dscott@laurentian.ca>
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

package OpenILS::WWW::AddedContent::OpenLibrary;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use OpenILS::WWW::AddedContent;
use OpenSRF::Utils::JSON;
use OpenSRF::EX qw/:try/;
use Data::Dumper;

# Edit the <added_content> section of /openils/conf/opensrf.xml
# Change <module> to:
#   <module>OpenILS::WWW::AddedContent::OpenLibrary</module>

my $AC = 'OpenILS::WWW::AddedContent';

# These URLs are always the same for OpenLibrary, so there's no advantage to
# pulling from opensrf.xml; we hardcode them here

# jscmd=details is unstable but includes goodies such as Table of Contents
my $base_url_details = 'http://openlibrary.org/api/books?format=json&jscmd=details&bibkeys=ISBN:';

# jscmd=data is stable and contains links to ebooks, excerpts, etc
my $base_url_data = 'http://openlibrary.org/api/books?format=json&jscmd=data&bibkeys=ISBN:';

my $cover_base_url = 'http://covers.openlibrary.org/b/isbn/';

sub new {
    my( $class, $args ) = @_;
    $class = ref $class || $class;
    return bless($args, $class);
}

# --------------------------------------------------------------------------
sub jacket_small {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_cover_response('small', $key));
}

sub jacket_medium {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_cover_response('medium', $key));

}
sub jacket_large {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_cover_response('large', $key));
}

# --------------------------------------------------------------------------

sub ebooks_html {
    my( $self, $key ) = @_;
    my $book_data_json = $self->fetch_data_response($key)->content();

    $logger->debug("$key: " . $book_data_json);

    my $ebook_html;
    
    my $book_data = OpenSRF::Utils::JSON->JSON2perl($book_data_json);
    my $book_key = (keys %$book_data)[0];

    # We didn't find a matching book; short-circuit our response
    if (!$book_key) {
        $logger->debug("$key: no found book");
        return 0;
    }

    my $ebooks_json = $book_data->{$book_key}->{ebooks};

    # No ebooks are available for this book; short-circuit
    if (!$ebooks_json or !scalar(@$ebooks_json)) {
        $logger->debug("$key: no ebooks");
        return 0;
    }

    # Check the availability of the ebooks
    my $available = $ebooks_json->[0]->{'availability'} || '';
    if (!$available) {
        $logger->debug("$key: no available ebooks");
        return 0;
    }

    # Build a basic list of available ebook types and their URLs
    # ebooks appears to be an array containing one element - a hash

    # First element of the hash is 'read_url' which is a URL to
    # Internet Archive online reader
    my $stream_url = $ebooks_json->[0]->{'read_url'} || '';
    if ($stream_url) {
        $ebook_html .= "<li class='ebook_stream'><a href='$stream_url'>Read online</a></li>\n";
        $logger->debug("$key: stream URL = $stream_url");
    }

    my $ebook_formats = $ebooks_json->[0]->{'formats'} || '';
    # Next elements are various ebook formats that are available
    foreach my $ebook (keys %{$ebook_formats}) {
        if ($ebook_formats->{$ebook} eq 'read_url') {
            next;
        }
        $ebook_html .= "<li class='ebook_$ebook'><a href='" . 
            $ebook_formats->{$ebook}->{'url'} . "'>" . uc($ebook) . "</a></li>\n";
    }

    $logger->debug("$key: $ebook_html");
    $self->send_html("<ul class='ebooks'>$ebook_html</ul>");
}

sub excerpt_html {
    my( $self, $key ) = @_;
    my $book_details_json = $self->fetch_details_response($key)->content();

    $logger->debug("$key: $book_details_json");

    my $excerpt_html;
    
    my $book_details = OpenSRF::Utils::JSON->JSON2perl($book_details_json);
    my $book_key = (keys %$book_details)[0];

    # We didn't find a matching book; short-circuit our response
    if (!$book_key) {
        $logger->debug("$key: no found book");
        return 0;
    }

    my $first_sentence = $book_details->{$book_key}->{first_sentence};
    if ($first_sentence) {
        $excerpt_html .= "<div class='sentence1'>$first_sentence</div>\n";
    }

    my $excerpts_json = $book_details->{$book_key}->{excerpts};
    if ($excerpts_json && scalar(@$excerpts_json)) {
        # Load up excerpt text with comments in tooltip
        foreach my $excerpt (@$excerpts_json) {
            my $text = $excerpt->{text};
            my $cmnt = $excerpt->{comment};
            $excerpt_html .= "<div class='ac_excerpt' title='$text'>$cmnt</div>\n";
        }
    }

    if (!$excerpt_html) {
        return 0;
    }

    $logger->debug("$key: $excerpt_html");
    $self->send_html("<div class='ac_excerpts'>$excerpt_html</div>");
}

=head1

OpenLibrary returns a JSON hash of zero or more book responses matching our
request. Each response may contain a table of contents within the details
section of the response.

For now, we check only the first response in the hash for a table of
contents, and if we find a table of contents, we transform it to a simple
HTML table.

=cut

sub toc_html {
    my( $self, $key ) = @_;
    my $book_details_json = $self->fetch_details_response($key)->content();

    $logger->debug("$key: " . $book_details_json);

    my $toc_html;
    
    my $book_details = OpenSRF::Utils::JSON->JSON2perl($book_details_json);
    my $book_key = (keys %$book_details)[0];

    # We didn't find a matching book; short-circuit our response
    if (!$book_key) {
        $logger->debug("$key: no found book");
        return 0;
    }

    my $toc_json = $book_details->{$book_key}->{details}->{table_of_contents};

    # No table of contents is available for this book; short-circuit
    if (!$toc_json or !scalar(@$toc_json)) {
        $logger->debug("$key: no TOC");
        return 0;
    }

    # Build a basic HTML table containing the section number, section title,
    # and page number. Some rows may not contain section numbers, we should
    # protect against empty page numbers too.
    foreach my $chapter (@$toc_json) {
	my $label = $chapter->{label};
        if ($label) {
            $label .= '. ';
        }
        my $title = $chapter->{title} || '';
        my $page_number = $chapter->{pagenum} || '';
 
        $toc_html .= '<tr>' .
            "<td class='toc_label'>$label</td>" .
            "<td class='toc_title'>$title</td>" .
            "<td class='toc_page'>$page_number</td>" .
            "</tr>\n";
    }

    $logger->debug("$key: $toc_html");
    $self->send_html("<table>$toc_html</table>");
}

sub toc_json {
    my( $self, $key ) = @_;
    my $toc = $self->send_json(
        $self->fetch_details_response($key)
    );
}

sub send_img {
    my($self, $response) = @_;
    return { 
        content_type => $response->header('Content-type'),
        content => $response->content, 
        binary => 1 
    };
}

sub send_json {
    my( $self, $content ) = @_;
    return 0 unless $content;

    return { content_type => 'text/plain', content => $content };
}

sub send_html {
    my( $self, $content ) = @_;
    return 0 unless $content;

    # Hide anything that might contain a link since it will be broken
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

    return { content_type => 'text/html', content => $HTML };
}

# returns the HTTP response object from the URL fetch
sub fetch_data_response {
    my( $self, $key ) = @_;
    my $url = $base_url_data . "$key";
    my $response = $AC->get_url($url);
    return $response;
}
# returns the HTTP response object from the URL fetch
sub fetch_details_response {
    my( $self, $key ) = @_;
    my $url = $base_url_details . "$key";
    my $response = $AC->get_url($url);
    return $response;
}

# returns the HTTP response object from the URL fetch
sub fetch_cover_response {
    my( $self, $size, $key ) = @_;

    my $response = $self->fetch_data_response($key)->content();

    my $book_data = OpenSRF::Utils::JSON->JSON2perl($response);
    my $book_key = (keys %$book_data)[0];

    # We didn't find a matching book; short-circuit our response
    if (!$book_key) {
        $logger->debug("$key: no found book");
        return 0;
    }

    my $covers_json = $book_data->{$book_key}->{cover};
    if (!$covers_json) {
        $logger->debug("$key: no covers for this book");
        return 0;
    }

    $logger->debug("$key: " . $covers_json->{$size});
    return $AC->get_url($covers_json->{$size}) || 0;
}


1;
