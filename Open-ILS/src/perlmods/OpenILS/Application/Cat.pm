use strict; use warnings;
package OpenILS::Application::Cat;
use OpenSRF::Application;
use OpenILS::Application::Cat::Utils;
use base qw/OpenSRF::Application/;
use Time::HiRes qw(time);
use JSON;
use OpenILS::Utils::Fieldmapper;

my $utils = "OpenILS::Application::Cat::Utils";

sub child_init {
	OpenSRF::Application->method_lookup( "blah" );
}


__PACKAGE__->register_method(
	method	=> "biblio_record_tree_retrieve",
	api_name	=> "open-ils.cat.biblio.record.tree.retrieve",
	argc		=> 1, 
	note		=> "Returns the tree associated with the nodeset of the given doc id"
);

sub biblio_record_tree_retrieve {
	my( $self, $client, $recordid ) = @_;

	my $name = "open-ils.storage.biblio.record_entry.nodeset.retrieve";
	my $method = $self->method_lookup($name);

	unless($method) {
		throw OpenSRF::EX::PANIC ("Could not lookup method $name");
	}

	my ($nodes) = $method->run($recordid);

	if(UNIVERSAL::isa($nodes,"OpenSRF::EX")) {
		throw $nodes;
	}

	return undef unless $nodes;
	my $tree = $utils->nodeset2tree( $nodes );
	return $tree;
}


__PACKAGE__->register_method(
	method	=> "biblio_record_tree_commit",
	api_name	=> "open-ils.cat.biblio.record.tree.commit",
	argc		=> 1, 
	note		=> "Walks the tree and commits any changed nodes " .
					"adds any new nodes, and deletes any deleted nodes",
);

sub biblio_record_tree_commit {
	my( $self, $client, $tree ) = @_;
	new Fieldmapper::biblio::record_node ($tree);
	my $nodeset = $utils->tree2nodeset($tree);
	my $hash = $utils->commit_nodeset( $nodeset );
	return $hash 
}




1;
