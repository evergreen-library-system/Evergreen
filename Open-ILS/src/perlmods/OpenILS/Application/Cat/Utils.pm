package OpenILS::Application::Cat::Utils;
use strict; use warnings;

use constant INTRA_DOC	=> 2;
use constant PARENT		=> 3;
use constant TYPE			=> 4;
use constant NAME			=> 5;
use constant VALUE		=> 6;
use constant CHILDREN	=> 7;
use constant ALTERED		=> 8;
use constant DELETED		=> 9;


# Converts an XML nodeset into a tree
sub nodeset2tree {
	my($class, $nodeset) = @_;

	my $size = @$nodeset;
	for my $index (0..$size) {

		my $child = $nodeset->[$index];

		if( $child and defined($child->[PARENT]) ) {
			my $parent = $nodeset->[$child->[PARENT]];
			push( @{$parent->[CHILDREN]}, $child );
		}
	}
	return $nodeset->[0];
}


my @_nodelist = ();
sub tree2nodeset {
	my($self, $node) = @_;

	if(!defined($node->[PARENT])) {
		@_nodelist = ();
	}

	push( @_nodelist, $node );
	for my $child (@{$node->[CHILDREN]}) {

		if(!defined($child->[PARENT])) {
			$child->[PARENT] = $node->[INTRA_DOC];
			$child->[ALTERED] = 1; #just to be sure
		}

		$self->tree2nodeset( $child );
	}
	$node->[CHILDREN] = undef;
	return \@_nodelist;
}

sub commit_nodeset {
	my($self, $nodeset) = @_;

	my $size = @$nodeset;
	my $offset = 0;

	for my $index (0..$size) {

		my $pos = $index + $offset;
		my $node = $nodeset->[$index];
		next unless $node;

		if( $node->[DELETED] ) {
			$offset--;
			return 0 unless _deletenode($node);
			next;
		}

		if(!defined($node->[INTRA_DOC])) {
			$node->[INTRA_DOC] = $pos;
			return 0 unless _addnode($node);
			next;
		}

		if( $node->[INTRA_DOC] != $pos ||
			 $node->[ALTERED] ) {

			$node->[INTRA_DOC] = $pos;
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
