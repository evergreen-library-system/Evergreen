package OpenILS::Application::Cat::Utils;
use strict; use warnings;
use OpenILS::Utils::Fieldmapper;
use XML::LibXML;
use XML::LibXSLT;
use OpenSRF::Utils::SettingsParser;



my $parser		= XML::LibXML->new();
my $xslt			= XML::LibXSLT->new();
my $xslt_doc	=	$parser->parse_file( "/pines/cvs/ILS/Open-ILS/xsl/MARC21slim2MODS.xsl" );
my $mods_sheet = $xslt->parse_stylesheet( $xslt_doc );

# ---------------------------------------------------------------------------
# Converts an XML nodeset into a tree
sub nodeset2tree {
	my($class, $nodeset) = @_;

	for my $child (@$nodeset) {
		next unless ($child and defined($child->parent_node));
		my $parent = $nodeset->[$child->parent_node];
		$parent->children([]) unless defined($parent->children); 
		push( @{$parent->children}, $child );
	}

	return $nodeset->[0];
}

# ---------------------------------------------------------------------------
# Converts a tree into an xml nodeset

my @_nodelist = ();
sub tree2nodeset {
	my($self, $node) = @_;

	if((ref($node) eq "ARRAY")) {
		$node = Fieldmapper::biblio::record_node->new($node);
	}

	return \@_nodelist unless $node;

	if(!defined($node->parent_node)) {
		@_nodelist = ();
	}

	push( @_nodelist, $node );

	if( $node->children() ) {

		for my $child (@{ $node->children() }) {

			$child =	 
				Fieldmapper::biblio::record_node->new($child);
	
			if(!defined($child->parent_node)) {
				$child->parent_node($node->intra_doc_id);
				$child->ischanged(1); #just to be sure
			}
	
			$self->tree2nodeset( $child );
		}
	}

	$node->children(undef);
	return \@_nodelist;
}

# ---------------------------------------------------------------------------
# Walks a nodeset and checks for insert, update, and delete and makes 
# appropriate db calls

sub commit_nodeset {
	my($self, $nodeset) = @_;

	my $size = @$nodeset;
	my $offset = 0;

	for my $index (0..$size) {

		my $pos = $index + $offset;
		my $node = $nodeset->[$index];
		next unless $node;

		if($node->isdeleted()) {
			$offset--;
			return 0 unless _deletenode($node);
			next;
		}

		if($node->isnew()) {
			$node->intra_doc_id($pos);
			return 0 unless _addnode($node);
			next;
		}

		if(	($node->intra_doc_id() 
				and $node->intra_doc_id() != $pos) ||
			 $node->ischanged() ) {

			$node->intra_doc_id($pos);
			return 0 unless _updatenode($node);
			next;
		}
	}
	return 1;
}

# send deletes, updates, then adds

sub _updatenode {
	my $node = shift;
	return 1;
}

sub _addnode {
	my $node = shift;
	return 1;
}

sub _deletenode {
	my $node = shift;
	return 1;
}
 
# ---------------------------------------------------------------------------


sub marcxml_doc_to_perl {
	my( $self, $marcxml_doc ) = @_;
	return undef unless $marcxml_doc;
	return OpenSRF::Utils::SettingsParser::XML2perl( $marcxml_doc->documentElement );
}


sub marcxml_doc_to_mods_perl {
	my( $self, $marcxml_doc ) = @_;

	print  "DOC:\n" . $marcxml_doc->toString(1) . "\n";
	my $mods = $mods_sheet->transform($marcxml_doc);
	print "MODS:\n " . $mods->toString(1). "\n";
	print "-------------------------------------------\n";

	my $perl = OpenSRF::Utils::SettingsParser::XML2perl( $mods->documentElement );
	return $perl->{mods} if $perl;
	return undef;
}

sub marcxml_nodeset_to_doc {
	my( $self, $nodes ) = @_;
	my $u = OpenILS::Utils::FlatXML->new();
	return $u->nodeset_to_xml( $nodes );
}

sub marcxml_doc_to_mods_nodeset {
	my( $self, $marcxml_doc ) = @_;
	my $mods = $mods_sheet->transform($marcxml_doc);
	my $u = OpenILS::Utils::FlatXML->new();
	my $nodeset = $u->xmldoc_to_nodeset( $mods );
	return $nodeset->nodeset if $nodeset;
	return undef;
}







1;
