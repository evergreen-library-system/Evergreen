package OpenILS::Application::Cat::Utils;
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use XML::LibXML;
use XML::LibXSLT;
use OpenSRF::Utils::SettingsParser;
use OpenILS::Utils::FlatXML;
use OpenILS::Utils::ModsParser;

my $mods_utils = OpenILS::Utils::ModsParser->new();



# -----------------------------------------------------------------------
# XXX This code is all deprecated.  Remove any traces and delete
# -----------------------------------------------------------------------



sub new {
	my($class) = @_;
	$class = ref($class) || $class;
	return bless( {}, $class );
}


# ---------------------------------------------------------------------------
# Converts an XML nodeset into a tree
# This method expects a blessed Fieldmapper::biblio::record_node object 
sub nodeset2tree {
	my($class, $nodeset) = @_;

	for my $child (@$nodeset) {
		next unless ($child and defined($child->parent_node));
		my $parent = $nodeset->[$child->parent_node];
		if( ! $parent ) {
			warn "No Parent For " . $child->intra_doc_id() . "\n";
		}
		$parent->children([]) unless defined($parent->children); 
		$child->isnew(0);
		$child->isdeleted(0);
		push( @{$parent->children}, $child );
	}

	return $nodeset->[0];
}


# ---------------------------------------------------------------------------
# Converts a tree into an xml nodeset
# This method expects a blessed Fieldmapper::biblio::record_node object 

sub tree2nodeset {

	my($self, $node, $newnodes) = @_;
	return $newnodes unless $node;

	if(!$newnodes) { $newnodes = []; }
	push( @$newnodes, $node );

	if( $node->children() ) {

		for my $child (@{ $node->children() }) {

			new Fieldmapper::biblio::record_node ($child);
			if(!defined($child->parent_node)) {
				$child->parent_node($node->intra_doc_id); 
				$child->ischanged(1); #just to be sure
			}
			$self->tree2nodeset( $child, $newnodes );
		}
	}

	$node->children([]); #we don't need them hanging around
	return $newnodes;
}


# Removes any deleted nodes from the tree
sub clean_nodeset {

	my($self, $nodeset) = @_;
	my @newnodes = ();
	for my $node (@$nodeset) {
		if(!$node->isdeleted() ) {
			push @newnodes, $node;
		}
	}

	return \@newnodes;
}




1;
