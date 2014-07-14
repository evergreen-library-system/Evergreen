package OpenILS::WWW::AddedContent::ContentCafe;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use OpenSRF::Utils::JSON;
use OpenSRF::EX qw/:try/;
use OpenILS::WWW::AddedContent;
use XML::LibXML;
use MIME::Base64;
use DateTime;

my $AC = 'OpenILS::WWW::AddedContent';

my $post_url = 'http://contentcafe2.btol.com/ContentCafe/ContentCafe.asmx/XmlPost';

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

sub identifier_order {
    my $self = shift;
    if ($self->{ContentCafe}->{identifier_order}) {
        my $order = [ split(',',$self->{ContentCafe}->{identifier_order}) ];
        return $order;
    }
    return ['isbn','upc'];
}

sub expects_keyhash {
    # we expect a keyhash as opposed to a simple scalar containing an ISBN
    return 1;
}

# --------------------------------------------------------------------------

# This function fetches everything and returns:
#     0 if we had no usable keys
#     0 if we had a lookup failure
#     A hash of format_type => result if you called that directly
sub fetch_all {
    my( $self, $keyhash ) = @_;
    my $doc = $self->fetch_xmldoc([
        'TocDetail', # toc_*
        'BiographyDetail', #anotes_*
        'ExcerptDetail', #excerpt_*
        'ReviewDetail', #reviews_*
        'AnnotationDetail', #summary_*
        {name => 'JacketDetail', attributes => [['Type','S'],['Encoding','HEX']]}, # jacket_small
        {name => 'JacketDetail', attributes => [['Type','M'],['Encoding','HEX']]}, # jacket_medium
        {name => 'JacketDetail', attributes => [['Type','L'],['Encoding','HEX']]}, # jacket_large
    ], $keyhash);
    return 0 unless defined $doc;
    my $resulthash = {
        toc_html        => $self->parse_toc_html($doc),
        toc_json        => $self->send_json($doc, 'TocItems'),
        toc_xml         => $self->send_xml($doc, 'TocItems'),
        anotes_html     => $self->parse_anotes_html($doc),
        anotes_json     => $self->send_json($doc, 'BiographyItems'),
        anotes_xml      => $self->send_xml($doc, 'BiographyItems'),
        excerpt_html    => $self->parse_excerpt_html($doc),
        excerpt_json    => $self->send_json($doc, 'ExcerptItems'),
        excerpt_xml     => $self->send_xml($doc, 'ExcerptItems'),
        reviews_html    => $self->parse_reviews_html($doc),
        reviews_json    => $self->send_json($doc, 'ReviewItems'),
        reviews_xml     => $self->send_xml($doc, 'ReviewItems'),
        summary_html    => $self->parse_summary_html($doc),
        summary_json    => $self->send_json($doc, 'AnnotationItems'),
        summary_xml     => $self->send_xml($doc, 'AnnotationItems'),
        jacket_small    => $self->parse_jacket($doc, 'S'),
        jacket_medium   => $self->parse_jacket($doc, 'M'),
        jacket_large    => $self->parse_jacket($doc, 'L')
    };
    return $resulthash;
}

# --------------------------------------------------------------------------
sub jacket_small {
    my( $self, $keyhash ) = @_;
    return $self->send_jacket( $keyhash, 'S' );
}

sub jacket_medium {
    my( $self, $keyhash ) = @_;
    return $self->send_jacket( $keyhash, 'M' );
}

sub jacket_large {
    my( $self, $keyhash ) = @_;
    return $self->send_jacket( $keyhash, 'L' );
}

# --------------------------------------------------------------------------

sub toc_html {
    my( $self, $keyhash ) = @_;
    my $doc = $self->fetch_xmldoc('TocDetail', $keyhash);
    return 0 unless defined $doc;
    return $self->parse_toc_html($doc);
}

sub parse_toc_html {
    my( $self, $doc ) = @_;
    my $html = '';
    my @nodes = $doc->findnodes('//cc:TocItems[*]');
    return 0 if (scalar(@nodes) < 1);
    @nodes = $nodes[0]->findnodes('.//cc:Toc');
    return 0 if (scalar(@nodes) < 1);
    foreach my $node ( @nodes ) {
        $html .= $node->textContent . '</P></P>';
    }
    return $self->send_html($html);
}

sub toc_xml {
    my( $self, $keyhash ) = @_;
    return $self->send_xml(
        $self->fetch_xmldoc('TocDetail', $keyhash),
        'TocItems');
}

sub toc_json {
    my( $self, $keyhash ) = @_;
    return $self->send_json(
        $self->fetch_xmldoc('TocDetail', $keyhash),
        'TocItems');
}

# --------------------------------------------------------------------------

sub anotes_html {
    my( $self, $keyhash ) = @_;
    my $doc = $self->fetch_xmldoc('BiographyDetail', $keyhash);
    return 0 unless defined $doc;
    return $self->parse_anotes_html($doc);
}

sub parse_anotes_html {
    my( $self, $doc ) = @_;
    my $html = '';
    my @nodes = $doc->findnodes('//cc:BiographyItems[*]');
    return 0 if (scalar(@nodes) < 1);
    @nodes = $nodes[0]->findnodes('.//cc:Biography');
    return 0 if (scalar(@nodes) < 1);
    foreach my $node ( @nodes ) {
        $html .= '<P class="biography">' . $node->textContent . '</P>';
    }
    return $self->send_html($html);
}

sub anotes_xml {
    my( $self, $keyhash ) = @_;
    return $self->send_xml(
        $self->fetch_xmldoc('BiographyDetail', $keyhash),
        'BiographyItems');
}

sub anotes_json {
    my( $self, $keyhash ) = @_;
    return $self->send_json(
        $self->fetch_xmldoc('BiographyDetail', $keyhash),
        'BiographyItems');
}


# --------------------------------------------------------------------------

sub excerpt_html {
    my( $self, $keyhash ) = @_;
    my $doc = $self->fetch_xmldoc('ExcerptDetail', $keyhash);
    return 0 unless defined $doc;
    return $self->parse_excerpt_html($doc);
}

sub parse_excerpt_html {
    my( $self, $doc ) = @_;
    my $html = '';
    my @nodes = $doc->findnodes('//cc:ExcerptItems[*]');
    return 0 if (scalar(@nodes) < 1);
    @nodes = $nodes[0]->findnodes('.//cc:Excerpt');
    return 0 if (scalar(@nodes) < 1);
    foreach my $node ( @nodes ) {
        $html .= $node->textContent;
    }
    return $self->send_html($html);
}

sub excerpt_xml {
    my( $self, $keyhash ) = @_;
    return $self->send_xml(
        $self->fetch_xmldoc('ExcerptDetail', $keyhash),
        'ExcerptItems');
}

sub excerpt_json {
    my( $self, $keyhash ) = @_;
    return $self->send_json(
        $self->fetch_xmldoc('ExcerptDetail', $keyhash),
        'ExcerptItems');
}

# --------------------------------------------------------------------------

sub reviews_html {
    my( $self, $keyhash ) = @_;
    my $doc = $self->fetch_xmldoc('ReviewDetail', $keyhash);
    return 0 unless defined $doc;
    return $self->parse_reviews_html($doc);
}

sub parse_reviews_html {
    my( $self, $doc ) = @_;
    my $html = '<ul>';
    my @nodes = $doc->findnodes('//cc:ReviewItems[*]');
    return 0 if (scalar(@nodes) < 1);
    @nodes = $nodes[0]->findnodes('.//cc:ReviewItem');
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
    my( $self, $keyhash ) = @_;
    return $self->send_xml(
        $self->fetch_xmldoc('ReviewDetail', $keyhash),
        'ReviewItems');
}

sub reviews_json {
    my( $self, $keyhash ) = @_;
    return $self->send_json(
        $self->fetch_xmldoc('ReviewDetail', $keyhash),
        'ReviewItems');
}

# --------------------------------------------------------------------------

sub summary_html {
    my( $self, $keyhash ) = @_;
    my $doc = $self->fetch_xmldoc('AnnotationDetail', $keyhash);
    return 0 unless defined $doc;
    return $self->parse_summary_html($doc);
}

sub parse_summary_html {
    my( $self, $doc ) = @_;
    my $html = '<ul>';
    my @nodes = $doc->findnodes('//cc:AnnotationItems[*]');
    return 0 if (scalar(@nodes) < 1);
    @nodes = $nodes[0]->findnodes('.//cc:AnnotationItem');
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
    my( $self, $keyhash ) = @_;
    return $self->send_xml(
        $self->fetch_xmldoc('AnnotationDetail', $keyhash),
        'AnnotationItems');
}

sub summary_json {
    my( $self, $keyhash ) = @_;
    return $self->send_json(
        $self->fetch_xmldoc('AnnotationDetail', $keyhash),
        'AnnotationItems');
}

# --------------------------------------------------------------------------

sub build_keylist {
    my ( $self, $keyhash ) = @_;
    my $keys = []; # Start with an empty array
    foreach my $identifier (@{$self->identifier_order}) {
        foreach my $key (@{$keyhash->{$identifier}}) {
            push @{$keys}, $key;
        }
    }
    return $keys;
}

sub send_json {
    my( $self, $doc, $contentNode ) = @_;
    return 0 unless defined $doc;
    my @nodes = $doc->findnodes('//cc:' . $contentNode . '[*]');
    return 0 if (scalar(@nodes) < 1);
    my $perl = OpenSRF::Utils::SettingsParser::XML2perl($nodes[0]);
    my $json = OpenSRF::Utils::JSON->perl2JSON($perl);
    return { content_type => 'text/plain', content => $json };
}

sub send_xml {
    my( $self, $doc, $contentNode ) = @_;
    return 0 unless defined $doc;
    my @nodes = $doc->findnodes('//cc:' . $contentNode . '[*]');
    return 0 if (scalar(@nodes) < 1);
    my $newdoc = XML::LibXML::Document->new( '1.0', 'utf-8' );
    my $clonenode = $nodes[0]->cloneNode(1);
    $newdoc->adoptNode($clonenode);
    $newdoc->setDocumentElement($clonenode);
    return { content_type => 'application/xml', content => $newdoc->toString() };
}

sub send_html {
    my( $self, $content ) = @_;

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

sub send_jacket {
    my( $self, $keyhash, $size ) = @_;

    my $doc = $self->fetch_xmldoc({name => 'JacketDetail', attributes => [['Type',$size],['Encoding','HEX']]}, $keyhash);
    return 0 unless defined $doc;

    return $self->parse_jacket($doc, $size);
}

sub parse_jacket {
    my( $self, $doc, $size ) = @_;
    my @nodes = $doc->findnodes("//cc:JacketItem[cc:Type/\@Code = '$size']");
    return 0 if (scalar(@nodes) < 1);

    my $jacketItem = shift(@nodes); # We only care about the first jacket
    my @formatNodes = $jacketItem->findnodes('./cc:Format');
    my $format = $formatNodes[0]->textContent;
    my @jacketNodes = $jacketItem->findnodes('./cc:Jacket');
    my $imageData = pack('H*',$jacketNodes[0]->textContent);

    return {
        content_type => 'image/' . lc($format),
        content => $imageData,
        binary => 1 
    };
}

# returns an XML document ready for parsing if $keyhash contained usable keys
# otherwise returns undef
sub fetch_xmldoc {
    my( $self, $contentTypes, $keyhash ) = @_;

    my $keys = $self->build_keylist($keyhash);
    return undef unless @{$keys};

    my $content = $self->fetch_response($contentTypes, $keys)->content;
    my $doc = XML::LibXML->new->parse_string($content);
    $doc->documentElement->setNamespace('http://ContentCafe2.btol.com', 'cc');
    return $doc;
}

# returns the HTTP response object from the URL fetch
sub fetch_response {
    my( $self, $contentTypes, $keys ) = @_;

    if (ref($contentTypes) ne 'ARRAY') {
        $contentTypes = [ $contentTypes ];
    }

    my $xmlRequest = XML::LibXML::Document->new( '1.0', 'utf-8' );
    my $root = $xmlRequest->createElementNS('http://ContentCafe2.btol.com','ContentCafe');
    $root->addChild($xmlRequest->createAttribute('DateTime', DateTime->now()->datetime));
    $xmlRequest->setDocumentElement($root);
    my $requestItems = $xmlRequest->createElement('RequestItems');
    $requestItems->addChild($xmlRequest->createAttribute('UserID', $self->userid));
    $requestItems->addChild($xmlRequest->createAttribute('Password', $self->password));
    $root->addChild($requestItems);

    foreach my $key (@{$keys}) {
        my $requestItem = $xmlRequest->createElement('RequestItem');
        my $keyNode = $xmlRequest->createElement('Key');
        $keyNode->addChild($xmlRequest->createTextNode($key));
        $requestItem->addChild($keyNode);

        foreach my $contentType (@{$contentTypes}) {
            my $contentNode = $xmlRequest->createElement('Content');
            if (ref($contentType) eq 'HASH') {
                $contentNode->addChild($xmlRequest->createTextNode($contentType->{name}));
                foreach my $contentAttribute (@{$contentType->{attributes}}) {
                    $contentNode->addChild($xmlRequest->createAttribute($contentAttribute->[0], $contentAttribute->[1]));
                }
            } else {
                $contentNode->addChild($xmlRequest->createTextNode($contentType));
            }
            $requestItem->addChild($contentNode);
        }

        $requestItems->addChild($requestItem);
    }
    my $response = $AC->post_url($post_url, $xmlRequest->toString);
    return $response;
}

1;
