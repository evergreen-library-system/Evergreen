use strict; use warnings;
package OpenILS::Application::Cat;
use OpenSRF::Application;
use OpenILS::Application::Cat::Utils;
use base qw/OpenSRF::Application/;




__PACKAGE__->register_method(
	method	=> "record_tree_retrieve",
	api_name	=> "open-ils.cat.record.tree.retrieve",
	argc		=> 1, 
	note		=> "Returns the tree associated with the nodeset of the given doc id"
);

sub record_tree_retrieve {
	my( $self, $client, $recordid ) = @_;

	my $name = "open-ils.storage.biblio.record_entry.nodeset.retrieve";
	my $method = $self->method_lookup($name);

	unless($method) {
		throw OpenSRF::EX::PANIC ("Could not lookup method $name");
	}

	my ($nodes) = $method->run($recordid);
	return undef unless $nodes;

	return OpenILS::Application::Cat::Utils->nodeset2tree( $nodes );
}



1;
