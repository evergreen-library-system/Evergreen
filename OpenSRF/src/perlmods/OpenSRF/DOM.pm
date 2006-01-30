use XML::LibXML;
use OpenSRF::Utils::Logger qw(:level);

package XML::LibXML::Element;
use OpenSRF::EX;

sub AUTOLOAD {
	my $self = shift;
	(my $name = $AUTOLOAD) =~ s/.*://;   # strip fully-qualified portion

	### Check for recursion
	my $calling_method = (caller(1))[3];
	my @info = caller(1);

	if( @info ) {
		if ($info[0] =~ /AUTOLOAD/) { @info = caller(2); }
	}
	unless( @info ) { @info = caller(); }
	if( $calling_method  and $calling_method eq "XML::LibXML::Element::AUTOLOAD" ) {
		throw OpenSRF::EX::PANIC ( "RECURSION! Caller [ @info ] | Object [ ".ref($self)." ]\n ** Trying to call $name", ERROR );
	}
	### Check for recursion
	
	#OpenSRF::Utils::Logger->debug( "Autoloading method for DOM: $AUTOLOAD on ".$self->toString, INTERNAL );

	my $new_node = OpenSRF::DOM::upcast($self);
	OpenSRF::Utils::Logger->debug( "Autoloaded to: ".ref($new_node), INTERNAL );

	return $new_node->$name(@_);
}



#--------------------------------------------------------------------------------
package OpenSRF::DOM;
use base qw/XML::LibXML OpenSRF/;

our %_NAMESPACE_MAP = (
	'http://open-ils.org/xml/namespaces/oils_v1' => 'oils',
);

our $_one_true_parser;

sub new {
	my $self = shift;
	return $_one_true_parser if (defined $_one_true_parser);
	$_one_true_parser = $self->SUPER::new(@_);
	$_one_true_parser->keep_blanks(0);
	$XML::LibXML::skipXMLDeclaration = 0;
	return $_one_true_parser = $self->SUPER::new(@_);
}

sub createDocument {
	my $self = shift;

	# DOM API: createDocument(namespaceURI, qualifiedName, doctype?)
	my $doc = XML::LibXML::Document->new("1.0", "UTF-8");
	my $el = $doc->createElement('root');

	$el->setNamespace('http://open-ils.org/xml/namespaces/oils_v1', 'oils', 1);
	$doc->setDocumentElement($el);

	return $doc;
}

my %_loaded_classes;
sub upcast {
	my $node = shift;
	return undef unless $node;

	my ($ns,$tag) = split ':' => $node->nodeName;

	return $node unless ($ns eq 'oils');

	my $class = "OpenSRF::DOM::Element::$tag";
	unless (exists $_loaded_classes{$class}) {
		$class->use;
		$_loaded_classes{$class} = 1;
	}
	if ($@) {
		OpenSRF::Utils::Logger->error("Couldn't use $class! $@");
	}

	#OpenSRF::Utils::Logger->debug("Upcasting ".$node->toString." to $class", INTERNAL);

	return bless $node => $class;
}

#--------------------------------------------------------------------------------
package OpenSRF::DOM::Node;
use base 'XML::LibXML::Node';

sub new {
	my $class = shift;
	return bless $class->SUPER::new(@_) => $class;
}

sub childNodes {
	my $self = shift;
	my @children = $self->_childNodes();
	return wantarray ? @children : OpenSRF::DOM::NodeList->new( @children );
}

sub attributes {
	my $self = shift;
	my @attr = $self->_attributes();
	return wantarray ? @attr : OpenSRF::DOM::NamedNodeMap->new( @attr );
}

sub findnodes {
	my ($node, $xpath) = @_;
	my @nodes = $node->_findnodes($xpath);
	if (wantarray) {
		return @nodes;
	} else {
		return OpenSRF::DOM::NodeList->new(@nodes);
	}
}


#--------------------------------------------------------------------------------
package OpenSRF::DOM::NamedNodeMap;
use base 'XML::LibXML::NamedNodeMap';

#--------------------------------------------------------------------------------
package OpenSRF::DOM::NodeList;
use base 'XML::LibXML::NodeList';

#--------------------------------------------------------------------------------
package OpenSRF::DOM::Element;
use base 'XML::LibXML::Element';

sub new {
	my $class = shift;

	# magically create the element (tag) name, or build a blank element
	(my $name = $class) =~ s/^OpenSRF::DOM::Element:://;
	if ($name) {
		$name = "oils:$name";
	} else {
		undef $name;
	}

	my $self = $class->SUPER::new($name);

	my %attrs = @_;
	for my $aname (keys %attrs) {
		$self->setAttribute($aname, $attrs{$aname});
	}

	return $self;
}

sub getElementsByTagName {
    my ( $node , $name ) = @_;
        my $xpath = "descendant::$name";
    my @nodes = $node->_findnodes($xpath);
        return wantarray ? @nodes : OpenSRF::DOM::NodeList->new(@nodes);
}

sub  getElementsByTagNameNS {
    my ( $node, $nsURI, $name ) = @_;
    my $xpath = "descendant::*[local-name()='$name' and namespace-uri()='$nsURI']";
    my @nodes = $node->_findnodes($xpath);
    return wantarray ? @nodes : OpenSRF::DOM::NodeList->new(@nodes);
}

sub getElementsByLocalName {
    my ( $node,$name ) = @_;
    my $xpath = "descendant::*[local-name()='$name']";
    my @nodes = $node->_findnodes($xpath);
    return wantarray ? @nodes : OpenSRF::DOM::NodeList->new(@nodes);
}

sub getChildrenByLocalName {
    my ( $node,$name ) = @_;
    my $xpath = "./*[local-name()='$name']";
    my @nodes = $node->_findnodes($xpath);
    return @nodes;
}

sub getChildrenByTagName {
    my ( $node, $name ) = @_;
    my @nodes = grep { $_->nodeName eq $name } $node->childNodes();
    return @nodes;
}

sub getChildrenByTagNameNS {
    my ( $node, $nsURI, $name ) = @_;
    my $xpath = "*[local-name()='$name' and namespace-uri()='$nsURI']";
    my @nodes = $node->_findnodes($xpath);
    return @nodes;
}

sub appendWellBalancedChunk {
    my ( $self, $chunk ) = @_;

    my $local_parser = OpenSRF::DOM->new();
    my $frag = $local_parser->parse_xml_chunk( $chunk );

    $self->appendChild( $frag );
}

package OpenSRF::DOM::Element::root;
use base 'OpenSRF::DOM::Element';

#--------------------------------------------------------------------------------
package OpenSRF::DOM::Text;
use base 'XML::LibXML::Text';


#--------------------------------------------------------------------------------
package OpenSRF::DOM::Comment;
use base 'XML::LibXML::Comment';

#--------------------------------------------------------------------------------
package OpenSRF::DOM::CDATASection;
use base 'XML::LibXML::CDATASection';

#--------------------------------------------------------------------------------
package OpenSRF::DOM::Document;
use base 'XML::LibXML::Document';

sub empty {
	my $self = shift;
	return undef unless (ref($self));
	$self->documentElement->removeChild($_) for $self->documentElement->childNodes;
	return $self;
}

sub new {
	my $class = shift;
	return bless $class->SUPER::new(@_) => $class;
}

sub getElementsByTagName {
	my ( $doc , $name ) = @_;
	my $xpath = "descendant-or-self::node()/$name";
	my @nodes = $doc->_findnodes($xpath);
	return wantarray ? @nodes : OpenSRF::DOM::NodeList->new(@nodes);
}

sub  getElementsByTagNameNS {
	my ( $doc, $nsURI, $name ) = @_;
	my $xpath = "descendant-or-self::*[local-name()='$name' and namespace-uri()='$nsURI']";
	my @nodes = $doc->_findnodes($xpath);
	return wantarray ? @nodes : OpenSRF::DOM::NodeList->new(@nodes);
}

sub getElementsByLocalName {
	my ( $doc,$name ) = @_;
	my $xpath = "descendant-or-self::*[local-name()='$name']";
	my @nodes = $doc->_findnodes($xpath);
	return wantarray ? @nodes : OpenSRF::DOM::NodeList->new(@nodes);
}

#--------------------------------------------------------------------------------
package OpenSRF::DOM::DocumentFragment;
use base 'XML::LibXML::DocumentFragment';

#--------------------------------------------------------------------------------
package OpenSRF::DOM::Attr;
use base 'XML::LibXML::Attr';

#--------------------------------------------------------------------------------
package OpenSRF::DOM::Dtd;
use base 'XML::LibXML::Dtd';

#--------------------------------------------------------------------------------
package OpenSRF::DOM::PI;
use base 'XML::LibXML::PI';

#--------------------------------------------------------------------------------
package OpenSRF::DOM::Namespace;
use base 'XML::LibXML::Namespace';

sub isEqualNode {
	my ( $self, $ref ) = @_;
	if ( $ref->isa("XML::LibXML::Namespace") ) {
		return $self->_isEqual($ref);
	}
	return 0;
}

#--------------------------------------------------------------------------------
package OpenSRF::DOM::Schema;
use base 'XML::LibXML::Schema';

1;
