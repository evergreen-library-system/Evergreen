use strict; use warnings;
package OpenILS::Utils::FlatXML;
use XML::LibXML;

my $_tC_mask = 1 << XML_TEXT_NODE | 1 << XML_COMMENT_NODE | 1 << XML_CDATA_SECTION_NODE | 1 << XML_DTD_NODE;
my $_val_mask = 1 << XML_ATTRIBUTE_NODE | 1 << XML_NAMESPACE_DECL;


my $parser = XML::LibXML->new();
$parser->keep_blanks(0);
sub new { return bless({},shift()); }

sub xml_to_doc {
	my($self, $xml) = @_;
	return $parser->parse_string( $xml );
}

sub xml_to_nodeset {
	my($self, $xml) = @_;
	return $self->_xml_to_nodeset(  $self->xml_to_doc( $xml ) );
}

sub xmlfile_to_nodeset {
	my($self, $xmlfile) = @_;
	return $self->_xml_to_nodeset(  $self->xmlfile_to_doc( $xmlfile ) );
}

sub xmlfile_to_doc {
	my($self, $xmlfile) = @_;
	return $parser->parse_file( $xmlfile );
}

sub nodeset_to_xml {
	my $self = shift;
	my $nodeset = shift;

	my $doc = XML::LibXML::Document->new;

	my %seen_ns;
	
	my @_xmllist;
	for my $node ( @{ $$nodeset{doclist} } ) {
		my $xml;

		if ( $node->{type} == XML_ELEMENT_NODE ) {

			$xml = $doc->createElement( $node->{name} );

			if ($node->{ns}) {
				my ($ns) = grep { $node->{ns} eq $_->{uri} } @{ $$nodeset{nslist} };
				$xml->setNamespace($ns->{uri}, $ns->{prefix}, 1) if ($ns->{prefix} || !$seen_ns{$ns->{uri}});
				$seen_ns{$ns->{uri}}++;
			}

		} elsif ( $node->{type} == XML_TEXT_NODE ) {
			$xml = $doc->createTextNode( $node->{value} );
			
		} elsif ( $node->{type} == XML_COMMENT_NODE ) {
			$xml = $doc->createComment( $node->{value} );
			
		} elsif ( $node->{type} == XML_ATTRIBUTE_NODE ) {

			if ($node->{ns}) {
				my ($ns) = grep { $node->{ns} eq $_->{uri} } @{ $$nodeset{nslist} };
				$_xmllist[$node->{parent}]->setAttributeNS($ns->{uri}, $node->{name}, $node->{value});
			} else {
				$_xmllist[$node->{parent}]->setAttribute($node->{name}, $node->{value});
			}

			next;
		}

		$_xmllist[$node->{id}] = $xml;

		if (defined $node->{parent}) {
			$_xmllist[$node->{parent}]->addChild($xml);
		}
	}

	$doc->setDocumentElement($_xmllist[0]);

	return $doc;
}

# --------------------------------------------------------------
# -- Builds a list of nodes from a given xml doc
my @nodeset = ();
my @nslist = ();
my $next_id = 0;
sub _xml_to_nodeset {

	my($self, $doc) = @_;

	return undef unless($doc);
	my $node = $doc->documentElement;
	return undef unless($node);

	_grab_namespaces($node);

	push @nodeset, { 
		id			=> 0,
		parent	=> undef,
		name		=> $node->localname,
		value		=> undef,
		type		=> $node->nodeType,
		ns			=> $node->namespaceURI
	};

	$self->_nodeset_recurse( $node, 0);

	# clear out the global variables
	my @tmp = @nodeset;
	my @tmpnslist = @nslist;
	@nodeset = ();
	@nslist = ();
	$next_id = 0;

	return  { doclist => [@tmp], nslist => [@tmpnslist] };
}

sub _grab_namespaces {
	my $node = shift;
	# add to the ns list if not alread there
	for my $ns ($node->getNamespaces) {
		if (my ($existing_ns) = grep { $_->{uri} eq $ns->value } @nslist) {
			$existing_ns->{prefix} = $ns->localname;
			next;
		}
		push @nslist, { prefix => $ns->localname, uri => $ns->value };
	}
}

sub _nodeset_recurse {

	my( $self, $node, $parent) = @_;
	return undef unless($node && $node->nodeType == 1);

	_grab_namespaces($node);

	for my $kid ( ($node->attributes, $node->childNodes) ) {
		next if ($kid->nodeType == 18);

		my $type = $kid->nodeType;

		push @nodeset, { 
			id			=> ++$next_id,
			parent	=> $parent, 
			name		=> $kid->localname,
			value		=> _grab_content( $kid, $type ),
			type		=> $type,
			ns			=> $kid->namespaceURI
		};

		return if ($type == 3);
		$self->_nodeset_recurse( $kid, $next_id);
	}
}

sub _grab_content {
	my $node = shift;
	my $type = 1 << shift();

	return undef if ($type & 1 << XML_ELEMENT_NODE);
	return $node->textContent if ($type & $_tC_mask);
	return $node->value if ($type & $_val_mask);
	return $node->getData if ($type & 1 << XML_PI_NODE);
}

1;
