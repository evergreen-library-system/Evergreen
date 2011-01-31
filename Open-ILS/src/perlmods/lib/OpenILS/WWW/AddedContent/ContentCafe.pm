package OpenILS::WWW::AddedContent::ContentCafe;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use OpenSRF::Utils::JSON;
use OpenSRF::EX qw/:try/;
use OpenILS::WWW::AddedContent;
use XML::LibXML;
use MIME::Base64;

my $AC = 'OpenILS::WWW::AddedContent';

my $base_url = 'http://contentcafe2.btol.com/ContentCafe/ContentCafe.asmx/Single';
my $cover_base_url = 'http://contentcafe2.btol.com/ContentCafe/Jacket.aspx';

sub new {
    my( $class, $args ) = @_;
    $class = ref $class || $class;
    return bless($args, $class);
}

sub userid {
    my $self = shift;
    return $self->{ContentCafe}->{userid};
}

sub password {
    my $self = shift;
    return $self->{ContentCafe}->{password};
}

sub return_behavior_on_no_jacket_image {
    my $self = shift;
    return $self->{ContentCafe}->{return_behavior_on_no_jacket_image};
}

# --------------------------------------------------------------------------
sub jacket_small {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_cover_response('S', $key));
}

sub jacket_medium {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_cover_response('M', $key));

}
sub jacket_large {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_cover_response('L', $key));
}

# --------------------------------------------------------------------------

sub toc_html {
    my( $self, $key ) = @_;
    my $xml = $self->fetch_content('TocDetail', $key);
    my $doc = XML::LibXML->new->parse_string($xml);
    $doc->documentElement->setNamespace('http://ContentCafe2.btol.com', 'cc');
    my $html = '';
    my @nodes = $doc->findnodes('//cc:Toc');
    return 0 if (scalar(@nodes) < 1);
    foreach my $node ( @nodes ) {
        $html .= $node->textContent . '</P></P>';
    }
    return $self->send_html($html);
}

sub toc_xml {
    my( $self, $key ) = @_;
    return $self->send_xml(
        $self->fetch_content('TocDetail', $key));
}

sub toc_json {
    my( $self, $key ) = @_;
    return $self->send_json(
        $self->fetch_content('TocDetail', $key));
}

# --------------------------------------------------------------------------

sub anotes_html {
    my( $self, $key ) = @_;
    my $xml = $self->fetch_content('BiographyDetail', $key);
    my $doc = XML::LibXML->new->parse_string($xml);
    $doc->documentElement->setNamespace('http://ContentCafe2.btol.com', 'cc');
    my $html = '';
    my @nodes = $doc->findnodes('//cc:Biography');
    return 0 if (scalar(@nodes) < 1);
    foreach my $node ( @nodes ) {
        $html .= '<P class="biography">' . $node->textContent . '</P>';
    }
    return $self->send_html($html);
}

sub anotes_xml {
    my( $self, $key ) = @_;
    return $self->send_xml(
        $self->fetch_content('BiographyDetail', $key));
}

sub anotes_json {
    my( $self, $key ) = @_;
    return $self->send_json(
        $self->fetch_content('BiographyDetail', $key));
}


# --------------------------------------------------------------------------

sub excerpt_html {
    my( $self, $key ) = @_;
    my $xml = $self->fetch_content('ExcerptDetail', $key);
    my $doc = XML::LibXML->new->parse_string($xml);
    $doc->documentElement->setNamespace('http://ContentCafe2.btol.com', 'cc');
    my $html = '';
    my @nodes = $doc->findnodes('//cc:Excerpt');
    return 0 if (scalar(@nodes) < 1);
    foreach my $node ( @nodes ) {
        $html .= $node->textContent;
    }
    return $self->send_html($html);
}

sub excerpt_xml {
    my( $self, $key ) = @_;
    return $self->send_xml(
        $self->fetch_content('ExcerptDetail', $key));
}

sub excerpt_json {
    my( $self, $key ) = @_;
    return $self->send_json(
        $self->fetch_content('ExcerptDetail', $key));
}

# --------------------------------------------------------------------------

sub reviews_html {
    my( $self, $key ) = @_;
    my $xml = $self->fetch_content('ReviewDetail', $key);
    my $doc = XML::LibXML->new->parse_string($xml);
    $doc->documentElement->setNamespace('http://ContentCafe2.btol.com', 'cc');
    my $html = '<ul>';
    my @nodes = $doc->findnodes('//cc:ReviewItem');
    return 0 if (scalar(@nodes) < 1);
    foreach my $node ( @nodes ) {
        my @s_nodes = $node->findnodes('./cc:Supplier');
        my @p_nodes = $node->findnodes('./cc:Publication');
        my @i_nodes = $node->findnodes('./cc:Issue');
        my @r_nodes = $node->findnodes('./cc:Review');
        $html .= '<li><b>' . (scalar(@p_nodes) ? $p_nodes[0]->textContent : '') . '</b>';
        if (scalar(@i_nodes) && scalar(@p_nodes)) { $html .= ' : '; }
        $html .= (scalar(@i_nodes) ? $i_nodes[0]->textContent : '') . '<br/>';
        $html .= (scalar(@r_nodes) ? $r_nodes[0]->textContent : '') . '</li>';
    }
    $html .= '</ul>';
    return $self->send_html($html);
}

sub reviews_xml {
    my( $self, $key ) = @_;
    return $self->send_xml(
        $self->fetch_content('ReviewDetail', $key));
}

sub reviews_json {
    my( $self, $key ) = @_;
    return $self->send_json(
        $self->fetch_content('ReviewDetail', $key));
}

# --------------------------------------------------------------------------

sub summary_html {
    my( $self, $key ) = @_;
    my $xml = $self->fetch_content('AnnotationDetail', $key);
    my $doc = XML::LibXML->new->parse_string($xml);
    $doc->documentElement->setNamespace('http://ContentCafe2.btol.com', 'cc');
    my $html = '<ul>';
    my @nodes = $doc->findnodes('//cc:AnnotationItem');
    return 0 if (scalar(@nodes) < 1);
    foreach my $node ( @nodes ) {
        my @s_nodes = $node->findnodes('./cc:Supplier');
        my @a_nodes = $node->findnodes('./cc:Annotation');
        $html .= '<li><b>' . (scalar(@s_nodes) ? $s_nodes[0]->textContent : '') . '</b><br/>';
        $html .= (scalar(@a_nodes) ? $a_nodes[0]->textContent : '') . '</li>';
    }
    $html .= '</ul>';
    return $self->send_html($html);
}

sub summary_xml {
    my( $self, $key ) = @_;
    return $self->send_xml(
        $self->fetch_content('AnnotationDetail', $key));
}

sub summary_json {
    my( $self, $key ) = @_;
    return $self->send_json(
        $self->fetch_content('AnnotationDetail', $key));
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
    my( $self, $contentType, $key ) = @_;
    return $self->fetch_response($contentType, $key)->content;
}

# returns the HTTP response object from the URL fetch
sub fetch_response {
    my( $self, $contentType, $key ) = @_;
    my $userid = $self->userid;
    my $password = $self->password;
    my $url = $base_url . "?UserID=$userid&Password=$password&Key=$key&Content=$contentType";
    return $AC->get_url($url);
}

# returns the HTTP response object from the URL fetch
sub fetch_cover_response {
    my( $self, $size, $key ) = @_;
    my $userid = $self->userid;
    my $password = $self->password;
    my $return = $self->return_behavior_on_no_jacket_image;
    my $url = $cover_base_url . "?UserID=$userid&Password=$password&Return=$return&Type=$size&Value=$key";
    return $AC->get_url($url);
}


1;
