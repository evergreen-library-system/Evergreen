package OpenILS::Application::Cat::Utils;
use strict; use warnings;
use OpenILS::Utils::Fieldmapper;

=head blah
use constant INTRA_DOC	=> 2;
use constant parent_node		=> 3;
use constant TYPE			=> 4;
use constant NAME			=> 5;
use constant VALUE		=> 6;
use constant CHILDREN	=> 7;
use constant ALTERED		=> 8;
use constant DELETED		=> 9;
=cut


# Converts an XML nodeset into a tree
sub nodeset2tree {
	my($class, $nodeset) = @_;

	my $size = @$nodeset;
	for my $index (0..$size) {

		my $child = 
			Fieldmapper::biblio::record_node->new($nodeset->[$index]);

		if( defined($child->parent_node) ) {
			my $parent = Fieldmapper::biblio::record_node->new($nodeset->[$child->parent_node]);
			$parent->children( [ $parent->children(), $child ]);
		}
	}
	return $nodeset->[0];
}


my @_nodelist = ();
sub tree2nodeset {
	my($self, $node) = @_;

	if((ref($node) eq "ARRAY")) {
		$node = Fieldmapper::biblio::record_node->new($node);
	}

	if(!$node) { return \@_nodelist; }

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

sub commit_nodeset {
	my($self, $nodeset) = @_;

	warn "3\n";
	my $size = @$nodeset;
	my $offset = 0;

	for my $index (0..$size) {

		my $pos = $index + $offset;
		my $node = $nodeset->[$index];
		next unless $node;
		$node = Fieldmapper::biblio::record_node->new($node);

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
 
1;
