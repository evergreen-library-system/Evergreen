package OpenILS::WWW::AddedContent::Syndetic;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use OpenSRF::Utils::JSON;
use OpenSRF::EX qw/:try/;
use OpenILS::WWW::AddedContent;
use XML::LibXML;
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

sub userid {
    my $self = shift;
    return $self->{userid};
}


# --------------------------------------------------------------------------
sub jacket_small {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_response('sc.gif', $key, 1));
}

sub jacket_medium {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_response('mc.gif', $key, 1));

}
sub jacket_large {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_response('lc.gif', $key, 1));
}

# --------------------------------------------------------------------------

sub toc_html {
    my( $self, $key ) = @_;
    return $self->send_html(
        $self->fetch_content('toc.html', $key));
}

sub toc_xml {
    my( $self, $key ) = @_;
    return $self->send_xml(
        $self->fetch_content('toc.xml', $key));
}

sub toc_json {
    my( $self, $key ) = @_;
    return $self->send_json(
        $self->fetch_content('toc.xml', $key));
}

# --------------------------------------------------------------------------

sub anotes_html {
    my( $self, $key ) = @_;
    return $self->send_html(
        $self->fetch_content('anotes.html', $key));
}

sub anotes_xml {
    my( $self, $key ) = @_;
    return $self->send_xml(
        $self->fetch_content('anotes.xml', $key));
}

sub anotes_json {
    my( $self, $key ) = @_;
    return $self->send_json(
        $self->fetch_content('anotes.xml', $key));
}


# --------------------------------------------------------------------------

sub excerpt_html {
    my( $self, $key ) = @_;
    return $self->send_html(
        $self->fetch_content('dbchapter.html', $key));
}

sub excerpt_xml {
    my( $self, $key ) = @_;
    return $self->send_xml(
        $self->fetch_content('dbchapter.xml', $key));
}

sub excerpt_json {
    my( $self, $key ) = @_;
    return $self->send_json(
        $self->fetch_content('dbchapter.xml', $key));
}

# --------------------------------------------------------------------------

sub reviews_html {
    my( $self, $key ) = @_;

    my %reviews;

    $reviews{ljreview} = $self->fetch_content('ljreview.html', $key); # Library Journal
    $reviews{pwreview} = $self->fetch_content('pwreview.html', $key); # Publishers Weekly
    $reviews{sljreview} = $self->fetch_content('sljreview.html', $key); # School Library Journal
    $reviews{chreview} = $self->fetch_content('chreview.html', $key); # CHOICE Review
    $reviews{blreview} = $self->fetch_content('blreview.html', $key); # Booklist Review
    $reviews{hbreview} = $self->fetch_content('hbreview.html', $key); # Horn Book Review
    $reviews{kireview} = $self->fetch_content('kireview.html', $key); # Kirkus Reviews
    #$reviews{abreview} = $self->fetch_content('abreview.html', $key); # Bookseller+Publisher
    #$reviews{criticasreview} = $self->fetch_content('criticasreview.html', $key); # Criticas
    $reviews{nyreview} = $self->fetch_content('nyreview.html', $key); # New York Times
    #$reviews{gdnreview} = $self->fetch_content('gdnreview.html', $key); # Guardian Review
    #$reviews{doodysreview} = $self->fetch_content('doodysreview.html', $key); # Doody's Reviews

    for(keys %reviews) {
        if( ! $self->data_exists($reviews{$_}) ) {
            delete $reviews{$_};
            next;
        }
        $reviews{$_} =~ s/<!.*?>//og; # Strip any doctype declarations
    }

    return 0 if scalar(keys %reviews) == 0;
    
    #my $html = "<div>";
    my $html;
    $html .= $reviews{$_} for keys %reviews;
    #$html .= "</div>";

    return $self->send_html($html);
}

# we have to aggregate the reviews
sub reviews_xml {
    my( $self, $key ) = @_;
    my %reviews;

    $reviews{ljreview} = $self->fetch_content('ljreview.xml', $key);
    $reviews{pwreview} = $self->fetch_content('pwreview.xml', $key);
    $reviews{sljreview} = $self->fetch_content('sljreview.xml', $key);
    $reviews{chreview} = $self->fetch_content('chreview.xml', $key);
    $reviews{blreview} = $self->fetch_content('blreview.xml', $key);
    $reviews{hbreview} = $self->fetch_content('hbreview.xml', $key);
    $reviews{kireview} = $self->fetch_content('kireview.xml', $key);
    #$reviews{abreview} = $self->fetch_content('abreview.xml', $key);
    #$reviews{criticasreview} = $self->fetch_content('criticasreview.xml', $key);
    $reviews{nyreview} = $self->fetch_content('nyreview.xml', $key);
    #$reviews{gdnreview} = $self->fetch_content('gdnreview.xml', $key);
    #$reviews{doodysreview} = $self->fetch_content('doodysreview.xml', $key);

    for(keys %reviews) {
        if( ! $self->data_exists($reviews{$_}) ) {
            delete $reviews{$_};
            next;
        }
        # Strip the xml and doctype declarations
        $reviews{$_} =~ s/<\?xml.*?>//og;
        $reviews{$_} =~ s/<!.*?>//og;
    }

    return 0 if scalar(keys %reviews) == 0;
    
    my $xml = "<reviews>";
    $xml .= $reviews{$_} for keys %reviews;
    $xml .= "</reviews>";

    return $self->send_xml($xml);
}


sub reviews_json {
    my( $self, $key ) = @_;
    return $self->send_json(
        $self->fetch_content('dbchapter.xml', $key));
}

# --------------------------------------------------------------------------


sub data_exists {
    my( $self, $data ) = @_;
    return 0 if $data =~ m/<title>error<\/title>/iog;
    return 1;
}


sub send_json {
    my( $self, $xml ) = @_;
    return 0 unless $self->data_exists($xml);
    my $doc;

    try {
        $doc = XML::LibXML->new->parse_string($xml);
    } catch Error with {
        my $err = shift;
        $logger->error("added content XML parser error: $err\n\n$xml");
        $doc = undef;
    };

    return 0 unless $doc;
    my $perl = OpenSRF::Utils::SettingsParser::XML2perl($doc->documentElement);
    my $json = OpenSRF::Utils::JSON->perl2JSON($perl);
    return { content_type => 'text/plain', content => $json };
}

sub send_xml {
    my( $self, $xml ) = @_;
    return 0 unless $self->data_exists($xml);
    return { content_type => 'application/xml', content => $xml };
}

sub send_html {
    my( $self, $content ) = @_;
    return 0 unless $self->data_exists($content);

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

sub send_img {
    my($self, $response) = @_;
    return { 
        content_type => $response->header('Content-type'),
        content => $response->content, 
        binary => 1 
    };
}

# returns the raw content returned from the URL fetch
sub fetch_content {
    my( $self, $page, $key ) = @_;
    return $self->fetch_response($page, $key)->content;
}

# returns the HTTP response object from the URL fetch
sub fetch_response {
    my( $self, $page, $key, $notype ) = @_;
    my $uname = $self->userid;
    my $url = $self->base_url . "?isbn=$key/$page&client=$uname" . (($notype) ? '' : "&type=rw12");
    return $AC->get_url($url);
}



1;
