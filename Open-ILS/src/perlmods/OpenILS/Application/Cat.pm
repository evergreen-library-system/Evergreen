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

sub _child_init {
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

	my $name = "open-ils.storage.biblio.record_marc.retrieve";
	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	my $request = $session->request( $name, $recordid );
	my $response = $request->recv();
	warn "got response from storage in retrieve for $recordid\n";

	if(!$response) { 
		throw OpenSRF::EX::ERROR ("No record in database with id $recordid");
	}

	if( $response->isa("OpenSRF::EX")) {
		throw $response ($response->stringify);
	}

	warn "grabbing content in retrieve\n";
	my $marcxml = $response->content;

	if(!$marcxml) {
		throw OpenSRF::EX::ERROR 
			("No record in database with id $recordid");
	}

	$request->finish();
	$session->disconnect();
	$session->kill_me();

	my $nodes = OpenILS::Utils::FlatXML->new()->xml_to_nodeset( $marcxml->marc ); 
	my $tree = $utils->nodeset2tree( $nodes->nodeset );
	$tree->owner_doc( $marcxml->id() );

	
	return $tree;
}

__PACKAGE__->register_method(
	method	=> "biblio_record_tree_commit",
	api_name	=> "open-ils.cat.biblio.record.tree.commit",
	argc		=> 3, #(session_id, biblio_tree ) 
	note		=> "Walks the tree and commits any changed nodes " .
					"adds any new nodes, and deletes any deleted nodes",
);

sub biblio_record_tree_commit {

	my( $self, $client, $user_session,  $tree ) = @_;
	new Fieldmapper::biblio::record_node ($tree);

	throw OpenSRF::EX::InvalidArg 
		("Not enough args to to open-ils.cat.biblio.record.tree.commit")
		unless ( $user_session and $client and $tree );

	OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

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

	my $session = OpenILS::Application::AppUtils->start_db_session();

	warn "Sending updated doc $docid to db\n";
	my $req = $session->request( "open-ils.storage.biblio.record_marc.update", $biblio );

	my $status = $req->recv();
	if(ref($status) and $status->isa("Error")) { 
		throw $status (" +++++++ Document Update Failed " . $status->stringify() ) ; 
	}

	OpenILS::Application::AppUtils->commit_db_session( $session );

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
	warn "looking up  record_marc retrieve " . time() . "\n";
	my $method = $self->method_lookup($name);
	unless($method) {
		throw OpenSRF::EX::PANIC ("Could not lookup method $name");
	}

	my $u = $utils->new();
	my $start = 1;


=head new way, fix me

	my $last_xml	= undef;
	my $session = OpenSRF::AppSession->create( "open-ils.storage" );

	# grab, process, wait, etc...
	for my $id (@recordids) {
		
		my $req = $session->request( $name, $id );
		if($last_xml) {
			if($start) {
				$u->start_mods_batch( $last_xml->marc );
				$start = 0;
			} else {
				$u->push_mods_batch( $last_xml->marc );
			}
			$last_xml = undef;
		}
		$req->wait_complete;
		$last_xml = $req->recv;
		if(UNIVERSAL::isa($last_xml,"OpenSRF::EX")) {
			throw $last_xml ($last_xml->stringify());;
		}
		$req->finish();
		$last_xml = $last_xml->content;
	}

	if($last_xml) { #grab the last one
		$u->push_mods_batch( $last_xml->marc );
	}

	$session->finish();
	$session->disconnect();
	$session->kill_me();

=cut


	for my $id (@recordids) {

		my ($marcxml) = $method->run($id);
		warn "retrieved marcxml at " . time() . "\n";
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

	warn "returning mods batch " . time . "\n";
	my $mods = $u->finish_mods_batch();
	return $mods;

}


__PACKAGE__->register_method(
	method	=> "biblio_record_record_metadata",
	api_name	=> "open-ils.cat.biblio.record.metadata.retrieve",
	argc		=> 1, #(session_id, biblio_tree ) 
	note		=> "Walks the tree and commits any changed nodes " .
					"adds any new nodes, and deletes any deleted nodes",
);

sub biblio_record_record_metadata {
	my( $self, $client, @ids ) = @_;

	if(!@ids){return undef;}

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $request = $session->request( 
			"open-ils.storage.biblio.record_entry.batch.retrieve", @ids );

	my $results = [];

	while( my $response = $request->recv() ) {

		if(!$response) {
			throw OpenSRF::EX::ERROR ("No Response from Storage");
		}
		if($response->isa("Error")) {
			throw $response ($response->stringify);
		}

		my $record_entry = $response->content;

		my $creator = $record_entry->creator;
		my $editor	= $record_entry->editor;

		my $info_session = OpenSRF::AppSession->create("open-ils.storage");

		# grab the creator's name
		my $creator_req = $info_session->request( 
			"open-ils.storage.actor.user.retrieve", $creator );
		my $creator_resp = $creator_req->recv();
		if(!$creator_resp) { $creator = ""; }
		if($creator_resp->isa("Error")){
			throw $creator_resp ($creator_resp);
		}
		$creator = $creator_resp->content;
		if($creator) {
			$creator = $creator->usrid;
		} else { $creator = ""; }

		my $editor_req = $info_session->request( 
			"open-ils.storage.actor.user.retrieve", $editor );
		my $editor_resp = $editor_req->recv();
		if(!$editor_resp) { $editor = ""; }
		if($editor_resp->isa("Error")){
			throw $editor_resp ($editor_resp);
		}
		$editor = $editor_resp->content;
		if($editor) {
			$editor = $editor->usrid;
		} else { $editor = ""; }


		$info_session->disconnect();
		$info_session->kill_me();

		$record_entry->creator( $creator );
		$record_entry->editor( $editor );

		push @$results, $record_entry;

	}

	$session->disconnect();
	$session->kill_me();

	return $results;

}




1;
