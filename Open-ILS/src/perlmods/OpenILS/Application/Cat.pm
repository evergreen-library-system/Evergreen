use strict; use warnings;
package OpenILS::Application::Cat;
use OpenSRF::Application;
use OpenILS::Application::Cat::Utils;
use base qw/OpenSRF::Application/;
use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use JSON;
use OpenILS::Utils::Fieldmapper;

my $utils = "OpenILS::Application::Cat::Utils";

sub child_init {
	try {
		OpenSRF::Application->method_lookup( "blah" );
	} catch Error with { 
		warn "Child Init Failed: " . shift() . "\n";
	};
}


__PACKAGE__->register_method(
	method	=> "biblio_record_tree_retrieve",
	api_name	=> "open-ils.cat.biblio.record.tree.retrieve",
	argc		=> 1, 
	note		=> "Returns the tree associated with the nodeset of the given doc id"
);

sub biblio_record_tree_retrieve {
	my( $self, $client, $recordid ) = @_;

	warn "In retrieve " . time() . "\n";
	my $name = "open-ils.storage.biblio.record_marc.retrieve";
	my $method = $self->method_lookup($name);

	unless($method) {
		throw OpenSRF::EX::PANIC ("Could not lookup method $name");
	}

	my ($marcxml) = $method->run($recordid);
	warn "After marxml retrieve " . time() . "\n";


	if(UNIVERSAL::isa($marcxml,"OpenSRF::EX")) {
		throw $marcxml;
	}

	return undef unless $marcxml;
#use Data::Dumper;
#	warn $marcxml->marc;

	my $nodes = OpenILS::Utils::FlatXML->new()->xml_to_nodeset( $marcxml->marc ); 
	my $tree = $utils->nodeset2tree( $nodes->nodeset );
	$tree->owner_doc( $marcxml->id() );
	warn "Returning Tree " . time() . "\n";
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

	# capture the doc id
	my $docid = $tree->owner_doc();

	# turn the tree into a nodeset
	my $nodeset = $utils->tree2nodeset($tree);
	$nodeset = $utils->clean_nodeset( $nodeset );

	use Data::Dumper;
	warn Dumper $nodeset;
	
	if(!defined($docid)) { # be sure
		for my $node (@$nodeset) {
			$docid = $node->owner_doc();
			last if defined($docid);
		}
	}

	# turn the nodeset into a doc
	my $marcxml = OpenILS::Utils::FlatXML->new()->nodeset_to_xml( $nodeset );

	my $biblio =  Fieldmapper::biblio::record_marc->new();
	$biblio->id( $docid );
	$biblio->marc( $marcxml->toString() );

	use Data::Dumper;
	warn "Biblio Object\n";
	warn Dumper $biblio;

	my $session = $utils->start_db_session();

	warn "Sending updated doc $docid to db\n";
	my $req = $session->request( 
		"open-ils.storage.biblio.record_marc.update", $biblio );

	my $status = $req->recv();
	if(ref($status) and $status->isa("Error")) { 
		warn " +++++++ Document Update Failed";
		warn $status->stringify() . "\n";
		throw $status (" +++++++ Document Update Failed " . $status->stringify() ) ; 
	}
	$utils->commit_db_session( $session );
	warn "Update Successful\n";


	# commit the altered nodeset nodes to the db
	#my $hash = $utils->commit_nodeset( $nodeset );
	# retrieve the altered tree back from the db and return it


	my $method = $self->method_lookup( "open-ils.cat.biblio.record.tree.retrieve" );
	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Unable to find method open-ils.cat.biblio.record.tree.retrieve");
	}
	my ($ans) = $method->run( $docid );
	warn "=================================================================\n";
	warn "=================================================================\n";
	use Data::Dumper;
	warn Dumper $ans;
	return $ans;
}

__PACKAGE__->register_method(
	method	=> "biblio_mods_slim_retrieve",
	api_name	=> "open-ils.cat.biblio.mods.slim.retrieve",
	argc		=> 1, 
	note		=> "Returns the displayable data from the MODS record with a given ID",
);

sub biblio_mods_slim_retrieve {
	my( $self, $client, $recordid ) = @_;

	my $name = "open-ils.storage.biblio.record_entry.nodeset.retrieve";
	my $method = $self->method_lookup($name);

	unless($method) {
		throw OpenSRF::EX::PANIC ("Could not lookup method $name");
	}

	my ($nodes) = $method->run($recordid);
	if(!$nodes) { warn "NOthing from storage"; return undef; }

	if(UNIVERSAL::isa($nodes,"OpenSRF::EX")) {
		throw $nodes;
	}

	my $u = $utils->new();
	$u->start_mods_batch( $nodes );

	my $mods = $u->finish_mods_batch();
	return $u->mods_perl_to_mods_slim( $mods );

}



1;
