use strict; use warnings;
package OpenILS::Application::Cat;
use OpenILS::Application::AppUtils;
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

	my $nodes = OpenILS::Utils::FlatXML->new()->xml_to_nodeset( $marcxml->marc ); 
	my $tree = $utils->nodeset2tree( $nodes->nodeset );
	$tree->owner_doc( $marcxml->id() );
	warn "Returning Tree " . time() . "\n";
	return $tree;
}

__PACKAGE__->register_method(
	method	=> "biblio_record_tree_commit",
	api_name	=> "open-ils.cat.biblio.record.tree.commit",
	argc		=> 2, #(session_id, biblio_tree ) 
	note		=> "Walks the tree and commits any changed nodes " .
					"adds any new nodes, and deletes any deleted nodes",
);

sub biblio_record_tree_commit {

	my( $self, $user_session, $client, $tree ) = @_;
	new Fieldmapper::biblio::record_node ($tree);

	$self->OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

	# capture the doc id
	my $docid = $tree->owner_doc();

	# turn the tree into a nodeset
	my $nodeset = $utils->tree2nodeset($tree);
	$nodeset = $utils->clean_nodeset( $nodeset );

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

	my $session = $utils->start_db_session();

	warn "Sending updated doc $docid to db\n";
	my $req = $session->request( "open-ils.storage.biblio.record_marc.update", $biblio );

	my $status = $req->recv();
	if(ref($status) and $status->isa("Error")) { 
		throw $status (" +++++++ Document Update Failed " . $status->stringify() ) ; 
	}

	$utils->commit_db_session( $session );

	my $method = $self->method_lookup( "open-ils.cat.biblio.record.tree.retrieve" );

	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Unable to find method open-ils.cat.biblio.record.tree.retrieve");
	}
	my ($ans) = $method->run( $docid );

	return $ans;
}

__PACKAGE__->register_method(
	method	=> "biblio_mods_slim_retrieve",
	api_name	=> "open-ils.cat.biblio.mods.slim.retrieve",
	argc		=> 1, 
	note		=> "Returns the displayable data from the MODS record with a given IDs " .
		"The first ID provided is considered the 'master' document, which means that " .
		"it's author, subject, etc. will be used.  Subjects are gathered from all docs."
);

sub biblio_mods_slim_retrieve {
	my( $self, $client, @recordids ) = @_;

	my $name = "open-ils.storage.biblio.record_marc.retrieve";
	my $method = $self->method_lookup($name);

	unless($method) {
		throw OpenSRF::EX::PANIC ("Could not lookup method $name");
	}

	my $u = $utils->new();
	my $start = 1;

	for my $id (@recordids) {
		my ($marcxml) = $method->run($id);
		if(!$marcxml) { warn "Nothing from storage"; return undef; }

		if(UNIVERSAL::isa($marcxml,"OpenSRF::EX")) {
			throw $marcxml ($marcxml->stringify());;
		}

		if($start) {
			$u->start_mods_batch( $marcxml->marc );
			$start = 0;
		} else {
			$u->push_mods_batch( $marcxml->marc );
		}
	}

	my $mods = $u->finish_mods_batch();
	return $mods;

}



1;
