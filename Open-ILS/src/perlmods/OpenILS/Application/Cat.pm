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

	use Data::Dumper;

	throw OpenSRF::EX::InvalidArg 
		("Not enough args to to open-ils.cat.biblio.record.tree.commit")
		unless ( $user_session and $client and $tree );

	my $user_obj = 
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

	warn "Starting db session\n";
	my $session = OpenILS::Application::AppUtils->start_db_session();

	my $x = _update_record_metadata( $session, { user => $user_obj, docid => $docid } );
	OpenILS::Application::AppUtils->rollback_db_session($session) unless $x;

	warn "Sending updated doc $docid to db\n";
	my $req = $session->request( "open-ils.storage.biblio.record_marc.update", $biblio );

	my $status = $req->recv();
	if( !$status || $status->isa("Error") || ! $status->content) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		if($status->isa("Error")) { throw $status ($status); }
		throw OpenSRF::EX::ERROR ("Error updating biblio record");
	}
	$req->finish();

	OpenILS::Application::AppUtils->commit_db_session( $session );

	$nodeset = OpenILS::Utils::FlatXML->new()->xmldoc_to_nodeset($marcxml);
	$tree = $utils->nodeset2tree($nodeset->nodeset);
	$tree->owner_doc($docid);

	$client->respond_complete($tree);



	# Send the doc to the wormer for wormizing
	warn "Starting worm session\n";
	my $wses = OpenSRF::AppSession->create("open-ils.worm");

	my $success = 0;
	my $wresp;
	for(0..9) {

		my $wreq = $wses->request( 
				"open-ils.worm.wormize.marc", $docid, $marcxml->toString );
		warn "Calling worm receive\n";
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

		warn "wormizing failed, rolling back\n";
		if($wresp and $wresp->isa("Error") ) {
			OpenILS::Application::AppUtils->rollback_db_session($session);
			throw $wresp ($wresp->stringify);
		}

		$wses->disconnect;
		$wses->kill_me;

		OpenILS::Application::AppUtils->rollback_db_session($session);

		throw OpenSRF::EX::ERROR ("Wormizing Failed for $docid" );
	}

	$wses->disconnect;
	$wses->kill_me;

	warn "Done wormizing\n";

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

		($creator, $editor) = _get_userid_by_id($creator, $editor);

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
		"open-ils.storage.actor.user.batch.retrieve.atomic", @ids );

	my $response = $request->recv();
	if(!$response) { return undef; }

	if($response->isa("Error")){
		throw $response ($response);
	}

	for my $u (@{$response->content}) {
		next unless ref($u);
		push @users, $u->usrname;
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




__PACKAGE__->register_method(
	method	=> "retrieve_copies",
	api_name	=> "open-ils.cat.asset.copy_tree.retrieve",
	argc		=> 2,  #(user_session, record_id)
	note		=> <<TEXT
	Returns the copies for a given bib record and for the users home library
TEXT
);

sub retrieve_copies {

	my( $self, $client, $user_session, $docid, $home_ou ) = @_;

	$docid = "$docid";

	#my $results = [];

	if(!$home_ou) {
		my $user_obj = 
			OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error
			$home_ou = $user_obj->home_ou;
	}

	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	
	# ------------------------------------------------------
	# grab the short name of the library location
	my $request = $session->request( 
			"open-ils.storage.actor.org_unit.retrieve", $home_ou );

	my $org_unit = $request->recv();
	if(!$org_unit) {
		throw OpenSRF::EX::ERROR 
			("No response from storage for org unit search");
	}
	if($org_unit->isa("Error")) { throw $org_unit ($org_unit->stringify);}
	my $location = $org_unit->content->shortname;
	$request->finish();
	# ------------------------------------------------------


	# ------------------------------------------------------
	# grab all the volumes for the given record and location
	my $search_hash = { record => $docid, owning_lib => $location };



	$request = $session->request( 
			"open-ils.storage.asset.call_number.search", $search_hash );

	my $volume;
	my @volume_ids;

	while( $volume = $request->recv() ) {

		if($volume->isa("Error")) { 
			throw $volume ($volume->stringify);}

		$volume = $volume->content;
		
		warn "Grabbing copies for volume: " . $volume->id . "\n";
		my $copies = 
			OpenILS::Application::AppUtils->simple_scalar_request( "open-ils.storage", 
				"open-ils.storage.asset.copy.search.call_number", $volume->id );

		$volume->copies($copies);

		$client->respond( $volume );

		#push @$results, $volume;

	}

	$request->finish();
	$session->finish();
	$session->disconnect();
	$session->kill_me();

	return undef;
	#return $results;
	
}




__PACKAGE__->register_method(
	method	=> "retrieve_copies_global",
	api_name	=> "open-ils.cat.asset.copy_tree.global.retrieve",
	argc		=> 2,  #(user_session, record_id)
	note		=> <<TEXT
	Returns all volumes and attached copies for a given bib record
TEXT
);

sub retrieve_copies_global {

	my( $self, $client, $user_session, $docid ) = @_;

	$docid = "$docid";

	my $session = OpenSRF::AppSession->create( "open-ils.storage" );

	# ------------------------------------------------------
	# grab all the volumes for the given record and location
	my $request = $session->request( 
			"open-ils.storage.asset.call_number.search.record", $docid );

	my $volumes = $request->recv();

		
	if($volumes->isa("Error")) { 
		throw $volumes ($volumes->stringify);}

	$volumes = $volumes->content;

	$request->finish();

	my $vol_hash = {};

	my @volume_ids;
	for my $volume (@$volumes) {
		$vol_hash->{$volume->id} = $volume;
	}

	my @ii = keys %$vol_hash;
	warn "Searching volumes @ii\n";
		
	$request = $session->request( 
			"open-ils.storage.asset.copy.search.call_number", keys %$vol_hash );
	
	while( my $copylist = $request->recv ) {
		
		if(UNIVERSAL::isa( $copylist, "Error")) {
			throw $copylist ($copylist->stringify);
		}

		warn "received copy list " . time() . "\n";
		$copylist = $copylist->content;

		my $vol;
		for my $copy (@$copylist) {
			$vol = $vol_hash->{$copy->call_number} unless $vol;
			$vol->copies([]) unless $vol->copies();
			push @{$vol->copies}, $copy;
		}
		$client->respond( $vol );
	}



	$request->finish();
	$session->finish();
	$session->disconnect();
	$session->kill_me();

	return undef;
	
}



__PACKAGE__->register_method(
	method	=> "create_copies",
	api_name	=> "open-ils.cat.asset.copy.batch.create",
	argc		=> 2,  #(user_session, record_id)
	note		=> "Adds the given copies to the database"
);

sub create_copies {
	my( $self, $client, $user_session, @copies ) = @_;

	my $user_obj = 
		OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

	for my $copy (@copies) {
		$copy->editor( $user_obj->id );
		$copy->creator( $user_obj->id );
	}

	my $session = OpenILS::Application::AppUtils->start_db_session;
	my $request = $session->request( 
			"open-ils.storage.asset.copy.batch.create", @copies );

	my $result = $request->recv();

	if(!$result) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		throw OpenSRF::EX::ERROR 
			("No response from storage on copy.batch.create");
	}

	if(UNIVERSAL::isa($result, "Error")) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		throw $result ($result->stringify);
	}

	OpenILS::Application::AppUtils->commit_db_session($session);
	return $result->content;

}


__PACKAGE__->register_method(
	method	=> "edit_copies",
	api_name	=> "open-ils.cat.asset.copy.batch.update",
	argc		=> 2,  #(user_session, record_id)
	note		=> "Updates the given copies",
);


sub edit_copies {
	my( $self, $client, $user_session, @copies ) = @_;

	my $user_obj = 
		OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

	for my $copy (@copies) {
		$copy->editor( $user_obj->id );
	}

	my $session = OpenILS::Application::AppUtils->start_db_session;
	my $request = $session->request( 
			"open-ils.storage.asset.copy.batch.update", @copies );

	my $result = $request->recv();

	if(!$result) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		throw OpenSRF::EX::ERROR 
			("No response from storage on copy.batch.update");
	}

	if(UNIVERSAL::isa($result, "Error")) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		throw $result ($result->stringify);
	}

	OpenILS::Application::AppUtils->commit_db_session($session);
	return $result->content;

}



__PACKAGE__->register_method(
	method	=> "delete_copies",
	api_name	=> "open-ils.cat.asset.copy.batch.delete",
	argc		=> 2,  #(user_session, record_id)
	note		=> "Removes the given copies from the database",
);


sub delete_copies {
	my( $self, $client, $user_session, @copies ) = @_;

	my $user_obj = 
		OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

	for my $copy (@copies) {
		$copy->editor( $user_obj->id );
	}


	my $session = OpenILS::Application::AppUtils->start_db_session;
	my $request = $session->request( 
			"open-ils.storage.asset.copy.batch.update", @copies );

	my $result = $request->recv();

	if(!$result) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		throw OpenSRF::EX::ERROR 
			("No response from storage on copy.batch.delete");
	}

	if(UNIVERSAL::isa($result, "Error")) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		throw $result ($result->stringify);
	}

	OpenILS::Application::AppUtils->commit_db_session($session);
	return $result->content;

}

1;
