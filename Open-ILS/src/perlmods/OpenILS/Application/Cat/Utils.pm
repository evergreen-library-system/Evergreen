package OpenILS::Application::Cat::Utils;
use strict; use warnings;

use constant INTRA_DOC	=> 2;
use constant PARENT		=> 3;
use constant TYPE			=> 4;
use constant NAME			=> 5;
use constant VALUE		=> 6;
use constant CHILDREN	=> 7;


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


sub tree2nodeset {

}
 

1;
