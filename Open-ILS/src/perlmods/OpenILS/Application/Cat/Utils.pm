package OpenILS::Application::Cat::Utils;
use strict; use warnings;
use OpenILS::Utils::Fieldmapper;

# ---------------------------------------------------------------------------
# Converts an XML nodeset into a tree
sub nodeset2tree {
	my($class, $nodeset) = @_;

	my $size = @$nodeset;
	for my $index (0..$size) {

		my $child = $nodeset->[$index];
		next unless $child;

		if( defined($child->parent_node) ) {
			my $parent = $nodeset->[$child->parent_node];
			$parent->children( 
					[ @{$parent->children() ? $parent->children() : [] }, $child ]);
		}
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

			next unless $child;
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

	warn "3\n";
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

		if($node->intra_doc_id() != $pos ||
			 $node->ischanged() ) {

			$node->intra_doc_id($pos);
			return 0 unless _updatenode($node);
			next;
		}
	}
	return 1;
}

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


sub nodeset_to_mods_nodeset {


}







1;
