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

	warn "turning into nodeset\n";
	my $nodes = OpenILS::Utils::FlatXML->new()->xml_to_nodeset( $marcxml->marc ); 
	warn "turning nodeset into tree\n";
	my $tree = $utils->nodeset2tree( $nodes->nodeset );

	$tree->owner_doc( $marcxml->id() );

	warn "returning tree\n";

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

	my $user_obj = 
		OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

	$client->respond("keepalive");

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

	warn "Starting db session\n";
	my $session = OpenILS::Application::AppUtils->start_db_session();

	my $x = _update_record_metadata( $session, { user => $user_obj, docid => $docid } );
	OpenILS::Application::AppUtils->rollback_db_session($session) unless $x;
	$client->respond("keepalive");


	warn "Sending updated doc $docid to db\n";
	my $req = $session->request( "open-ils.storage.biblio.record_marc.update", $biblio );

	my $status = $req->recv();
	if( !$status || $status->isa("Error") || ! $status->content) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		if($status->isa("Error")) { throw $status ($status); }
		throw OpenSRF::EX::ERROR ("Error updating biblio record");
	}
	$req->finish();
	
	# Send the doc to the wormer for wormizing
	warn "Starting worm session\n";
	my $wses = OpenSRF::AppSession->create("open-ils.worm");

	my $success = 0;
	my $wresp;
	for(0..1) {

		my $wreq = $wses->request( 
				"open-ils.worm.wormize.marc", $docid, $marcxml->toString );
		$wresp = $wreq->recv();

		if( $wresp && $wresp->can("content") and $wresp->content ) {
			$success = 1;
			$wreq->finish();
			last;
		}

		warn "Looping in worm call\n";
		$wreq->finish();
	}

	if( !$success ) {


		if($wresp and $wresp->isa("Error") ) {
			$wses->disconnect;
			$wses->kill_me;
			throw $wresp ($wresp->stringify);
		}

		$wses->disconnect;
		$wses->kill_me;

		OpenILS::Application::AppUtils->rollback_db_session($session);

		return undef;
	}


	$client->respond("keepalive");

	$wses->disconnect;
	$wses->kill_me;

	warn "committing db session\n";
	OpenILS::Application::AppUtils->commit_db_session( $session );

	my $method = $self->method_lookup( "open-ils.cat.biblio.record.tree.retrieve" );

	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Unable to find method open-ils.cat.biblio.record.tree.retrieve"); }

	my ($ans) = $method->run( $docid );

	warn "Returning from commit\n";

	return $ans;
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

		($creator, $editor) = _get_userid_by_id($creator, $editor) || ("","");

		$record_entry->creator( $creator );
		$record_entry->editor( $editor );

		push @$results, $record_entry;

	}

	$session->disconnect();
	$session->kill_me();

	return $results;

}

# gets the username
sub _get_userid_by_id {

	my @ids = @_;
	my @users;

	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	my $request = $session->request( 
		"open-ils.storage.actor.user.batch.retrieve", @ids );

	my $response = $request->recv();
	if(!$response) { return undef; }

	if($response->isa("Error")){
		throw $response ($response);
	}

	for my $u (@{$response->content}) {
		next unless ref($u);
		push @users, $u->usrid;
	}

	$request->finish;
	$session->disconnect;
	$session->kill_me();

	return @users;
}

# open-ils.storage.actor.user.search.usrid

sub _get_id_by_userid {

	my @users = @_;
	my @ids;

	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	my $request = $session->request( 
		"open-ils.storage.actor.user.search.usrid", @users );

	my $response = $request->recv();
	if(!$response) { return undef; }

	if($response->isa("Error")){
		throw $response ($response);
	}

	for my $u (@{$response->content}) {
		next unless ref($u);
		push @ids, $u->id();
	}

	$request->finish;
	$session->disconnect;
	$session->kill_me();

	return @ids;
}


# commits metadata objects to the db
sub _update_record_metadata {

	my ($session, @docs ) = @_;

	for my $doc (@docs) {

		my $user_obj = $doc->{user};
		my $docid = $doc->{docid};

		warn "Updating metata for doc $docid\n";

		# ----------------------------------------
		# grab the meta information  and update it
		my $user_session = OpenSRF::AppSession->create("open-ils.storage");
		my $user_request = $user_session->request( 
			"open-ils.storage.biblio.record_entry.retrieve", $docid );
		my $meta = $user_request->recv();

		if(!$meta) {
			throw OpenSRF::EX::ERROR ("No meta info returned for biblio $docid");
		}
		if($meta->isa("Error")) {
			throw $meta ($meta->stringify);
		}

		$meta = $meta->content;
		my ($id) = _get_id_by_userid($user_obj->usrid);
		warn "got $id from _get_id_by_userid\n";
		$meta->editor($id);

		$user_request->finish;
		$user_session->disconnect;
		$user_session->kill_me;
		# -------------------------------------
		
		warn "Grabbed the record, updating and moving on\n";

		my $request = $session->request( 
			"open-ils.storage.biblio.record_entry.update", $meta );

		my $response = $request->recv();
		if(!$response) { 
			throw OpenSRF::EX::ERROR 
				("Error commit record metadata for " . $meta->id);
		}

		if($response->isa("Error")){ 
			throw $response ($response->stringify); 
		}

		$request->finish;
	}

	warn "committing metarecord update\n";
	return 1;
}





1;
