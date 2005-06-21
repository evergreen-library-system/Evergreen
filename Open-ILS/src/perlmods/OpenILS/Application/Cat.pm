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
use XML::LibXML;
use Data::Dumper;
use OpenILS::Utils::FlatXML;

my $apputils = "OpenILS::Application::AppUtils";

my $utils = "OpenILS::Application::Cat::Utils";


__PACKAGE__->register_method(
	method	=> "biblio_record_tree_import",
	api_name	=> "open-ils.cat.biblio.record.tree.import",
);

sub biblio_record_tree_import {
	my( $self, $client, $user_session, $tree) = @_;
	my $user_obj = $apputils->check_user_session($user_session);

	warn "importing new record " . Dumper($tree) . "\n";

	my $nodeset = $utils->tree2nodeset($tree);
	warn "turned into nodeset " . Dumper($nodeset) . "\n";

	# copy the doc so that we can mangle the namespace.  
	my $marcxml = OpenILS::Utils::FlatXML->new()->nodeset_to_xml($nodeset);
	my $copy_marcxml = XML::LibXML->new->parse_string($marcxml->toString);

	$marcxml->documentElement->setNamespace( "http://www.loc.gov/MARC21/slim", "marc", 1 );
	my $tcn;


	warn "Starting db session in import\n";
	my $session = $apputils->start_db_session();
	my $source = 2; # system local source

	my $xpath = '//controlfield[@tag="001"]';
	$tcn = $marcxml->documentElement->findvalue($xpath);
	if(_tcn_exists($session, $tcn)) {$tcn = undef;}
	my $tcn_source = "External";


	if(!$tcn) {
		$xpath = '//datafield[@tag="020"]';
		$tcn = $marcxml->documentElement->findvalue($xpath);
		$tcn_source = "ISBN";
		if(_tcn_exists($session, $tcn)) {$tcn = undef;}
	}

	if(!$tcn) { 
		$xpath = '//datafield[@tag="022"]';
		$tcn = $marcxml->documentElement->findvalue($xpath);
		$tcn_source = "ISSN";
		if(_tcn_exists($session, $tcn)) {$tcn = undef;}
	}

	if(!$tcn) {
		$xpath = '//datafield[@tag="010"]';
		$tcn = $marcxml->documentElement->findvalue($xpath);
		$tcn_source = "LCCN";
		if(_tcn_exists($session, $tcn)) {$tcn = undef;}
	}

	if(!$tcn) {
		$xpath = '//datafield[@tag="035"]';
		$tcn = $marcxml->documentElement->findvalue($xpath);
		$tcn_source = "System";
		if(_tcn_exists($session, $tcn)) {$tcn = undef;}
	}

	warn "Record import with tcn: $tcn and source $tcn_source\n";

	my $record = Fieldmapper::biblio::record_entry->new;

	$record->source($source);
	$record->tcn_source($tcn_source);
	$record->tcn_value($tcn);
	$record->creator($user_obj->id);
	$record->editor($user_obj->id);
	$record->marc($copy_marcxml->toString);


	my $req = $session->request(
		"open-ils.storage.direct.biblio.record_entry.create",
		$record );
	my $id = $req->gather(1);

	my $wreq = $session->request("open-ils.worm.wormize", $id);
	$wreq->gather(1);

	$apputils->commit_db_session($session);

	return $self->biblio_record_tree_retrieve($client, $id);
}

sub _tcn_exists {
	my $session = shift;
	my $tcn = shift;

	if(!$tcn) {return 0;}

	my $req = $session->request(      
		"open-ils.storage.direct.biblio.record_entry.search.tcn_value",
		$tcn );
	my $recs = $req->gather(1);

	if($recs and $recs->[0]) {
		return 1;
	}
	return 0;
}



__PACKAGE__->register_method(
	method	=> "biblio_record_tree_retrieve",
	api_name	=> "open-ils.cat.biblio.record.tree.retrieve",
);

sub biblio_record_tree_retrieve {

	my( $self, $client, $recordid ) = @_;

	my $name = "open-ils.storage.direct.biblio.record_entry.retrieve";
	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	my $request = $session->request( $name, $recordid );
	my $marcxml = $request->gather(1);

	if(!$marcxml) {
		throw OpenSRF::EX::ERROR 
			("No record in database with id $recordid");
	}

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

	throw OpenSRF::EX::InvalidArg 
		("Not enough args to to open-ils.cat.biblio.record.tree.commit")
		unless ( $user_session and $tree );

	my $user_obj = 
		OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

	# capture the doc id
	my $docid = $tree->owner_doc();
	my $session = OpenILS::Application::AppUtils->start_db_session();

	warn "Retrieving biblio record from storage for update\n";

	my $req1 = $session->request(
			"open-ils.storage.direct.biblio.record_entry.batch.retrieve", 
			$docid );
	my $biblio = $req1->gather(1);

	warn "retrieved doc $docid\n";


	# turn the tree into a nodeset
	my $nodeset = $utils->tree2nodeset($tree);
	$nodeset = $utils->clean_nodeset($nodeset);

	if(!defined($docid)) { # be sure
		for my $node (@$nodeset) {
			$docid = $node->owner_doc();
			last if defined($docid);
		}
	}

	# turn the nodeset into a doc
	my $marcxml = OpenILS::Utils::FlatXML->new()->nodeset_to_xml( $nodeset );

	$biblio->marc( $marcxml->toString() );

	warn "Starting db session\n";

	my $x = _update_record_metadata( $session, { user => $user_obj, docid => $docid } );
	OpenILS::Application::AppUtils->rollback_db_session($session) unless $x;

	warn "Sending updated doc $docid to db\n";
	my $req = $session->request( "open-ils.storage.direct.biblio.record_entry.update", $biblio );

	$req->wait_complete;
	my $status = $req->recv();
	if( !$status || $status->isa("Error") || ! $status->content) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		if($status->isa("Error")) { throw $status ($status); }
		throw OpenSRF::EX::ERROR ("Error updating biblio record");
	}
	$req->finish();

	# Send the doc to the wormer for wormizing
	warn "Starting worm session\n";

	my $success = 0;
	my $wresp;

	my $wreq = $session->request( "open-ils.worm.wormize", $docid );

	try {
		$wreq->gather(1);

	} catch Error with {
		my $e = shift;
		warn "wormizing failed, rolling back\n";
		OpenILS::Application::AppUtils->rollback_db_session($session);

		if($e) { throw $e ($e); }
		throw OpenSRF::EX::ERROR ("Wormizing Failed for $docid" );
	};

	OpenILS::Application::AppUtils->commit_db_session( $session );

	$nodeset = OpenILS::Utils::FlatXML->new()->xmldoc_to_nodeset($marcxml);
	$tree = $utils->nodeset2tree($nodeset->nodeset);
	$tree->owner_doc($docid);

#	$client->respond_complete($tree);

	warn "Done wormizing\n";

	use Data::Dumper;
	warn "Returning tree:\n";
	warn Dumper $tree;
	return $tree;

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
			"open-ils.storage.direct.biblio.record_entry.batch.retrieve", @ids );

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

	$request->finish;
	$session->disconnect();
	$session->finish();

	return $results;

}

# gets the username
sub _get_userid_by_id {

	my @ids = @_;
	my @users;

	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	my $request = $session->request( 
		"open-ils.storage.direct.actor.user.batch.retrieve.atomic", @ids );

	$request->wait_complete;
	my $response = $request->recv();
	if(!$request->complete) { return undef; }

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

sub _get_id_by_userid {

	my @users = @_;
	my @ids;

	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	my $request = $session->request( 
		"open-ils.storage.direct.actor.user.search.usrname", @users );

	$request->wait_complete;
	my $response = $request->recv();
	if(!$request->complete) { 
		throw OpenSRF::EX::ERROR ("no response from storage on user retrieve");
	}

	if(UNIVERSAL::isa( $response, "Error")){
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

		my $request = $session->request( 
			"open-ils.storage.direct.biblio.record_entry.retrieve", $docid );
		my $record = $request->gather(1);

		warn "retrieved record\n";
		my ($id) = _get_id_by_userid($user_obj->usrname);

		warn "got $id from _get_id_by_userid\n";
		$record->editor($id);
		
		warn "Grabbed the record, updating and moving on\n";

		$request = $session->request( 
			"open-ils.storage.direct.biblio.record_entry.update", $record );
		$request->gather(1);
	}

	warn "committing metarecord update\n";

	return 1;
}



__PACKAGE__->register_method(
	method	=> "orgs_for_title",
	api_name	=> "open-ils.cat.actor.org_unit.retrieve_by_title"
);

sub orgs_for_title {
	my( $self, $client, $record_id ) = @_;

	my $vols = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.asset.call_number.search.record",
		$record_id );

	my $orgs = { map {$_->owning_lib => 1 } @$vols };
	return [ keys %$orgs ];
}



__PACKAGE__->register_method(
	method	=> "retrieve_copies",
	api_name	=> "open-ils.cat.asset.copy_tree.retrieve");

__PACKAGE__->register_method(
	method	=> "retrieve_copies",
	api_name	=> "open-ils.cat.asset.copy_tree.global.retrieve");

# user_session may be null/undef
sub retrieve_copies {

	my( $self, $client, $user_session, $docid, @org_ids ) = @_;

	if(ref($org_ids[0])) { @org_ids = @{$org_ids[0]}; }

	$docid = "$docid";

	warn " $$ retrieving copy tree for orgs @org_ids and doc $docid at " . time() . "\n";

	# grabbing copy trees should be available for everyone..
	if(!@org_ids and $user_session) {
		my $user_obj = 
			OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error
			@org_ids = ($user_obj->home_ou);
	}

	if( $self->api_name =~ /global/ ) {
		warn "performing global copy_tree search for $docid\n";
		return _build_volume_list( { record => $docid } );

	} else {

		my @all_vols;
		for my $orgid (@org_ids) {
			my $vols = _build_volume_list( 
					{ record => $docid, owning_lib => $orgid } );
			warn "Volumes built for org $orgid\n";
			push( @all_vols, @$vols );
		}
		
		warn " $$ Finished copy_tree at " . time() . "\n";
		return \@all_vols;
	}

	return undef;
}


sub _build_volume_list {
	my $search_hash = shift;

	my	$session = OpenSRF::AppSession->create( "open-ils.storage" );
	

	my $request = $session->request( 
			"open-ils.storage.direct.asset.call_number.search.atomic", $search_hash );

	my $vols = $request->gather(1);
	my @volumes;

	for my $volume (@$vols) {

		warn "Grabbing copies for volume: " . $volume->id . "\n";
		my $creq = $session->request(
			"open-ils.storage.direct.asset.copy.search.call_number", 
			$volume->id );
		my $copies = $creq->gather(1);

		$volume->copies($copies);

		push( @volumes, $volume );
	}


	$session->disconnect();
	return \@volumes;

}


# -----------------------------------------------------------------
# Fleshed volume tree batch add/update.  This does everything a 
# volume tree could want, add, update, delete
# -----------------------------------------------------------------
__PACKAGE__->register_method(
	method	=> "volume_tree_fleshed_update",
	api_name	=> "open-ils.cat.asset.volume_tree.fleshed.batch.update",
);
sub volume_tree_fleshed_update {

	my( $self, $client, $user_session, $volumes ) = @_;
	return undef unless $volumes;
	my $user_obj = $apputils->check_user_session($user_session);

	my $session = $apputils->start_db_session();
	warn "Looping on volumes in fleshed volume tree update\n";

	# cycle through the volumes provided and update/create/delete where necessary
	for my $volume (@$volumes) {

		warn "updating volume " . $volume->id . "\n";

		my $update_copy_list = $volume->copies;


		if( $volume->isdeleted) {
			my $status = _delete_volume($session, $volume);
			if(!$status) {
				throw OpenSRF::EX::ERROR
					("Volume delete failed for volume " . $volume->id);
			}

		} elsif( $volume->isnew ) {

			$volume->clear_id;
			$volume->editor($user_obj->id);
			$volume->creator($user_obj->id);
			$volume = _add_volume($session, $volume);

		} elsif( $volume->ischanged ) {

			$volume->editor($user_obj->id);
			_update_volume($session, $volume);
		}


		if( ! $volume->isdeleted ) {
			for my $copy (@{$update_copy_list}) {
	
				$copy->editor($user_obj->id);
				warn "updating copy for volume " . $volume->id . "\n";
	
				if( $copy->isnew ) {
	
					$copy->clear_id;
					$copy->call_number($volume->id);
					$copy->creator($user_obj->id);
					$copy = _fleshed_copy_update($session,$copy,$user_obj->id);
	
				} elsif( $copy->ischanged ) {
					$copy->call_number($volume->id);
					$copy = _fleshed_copy_update($session, $copy, $user_obj->id);
	
				} elsif( $copy->isdeleted ) {
					warn "Deleting copy " . $copy->id . " for volume " . $volume->id . "\n";
					my $status = _fleshed_copy_update($session, $copy, $user_obj->id);
					warn "Copy delete returned a status of $status\n";
				}
			}
		}
	}
	$apputils->commit_db_session($session);
	return scalar(@$volumes);
}


sub _delete_volume {
	my( $session, $volume ) = @_;

	#$volume = _find_volume($session, $volume);
	warn "Deleting volume " . $volume->id . "\n";

	my $copies = $session->request(
		"open-ils.storage.direct.asset.copy.search.call_number",
		$volume->id )->gather(1);
	if(@$copies) {
		throw OpenSRF::EX::ERROR 
			("Cannot remove volume with copies attached");
	}

	my $req = $session->request(
		"open-ils.storage.direct.asset.call_number.delete",
		$volume );
	return $req->gather(1);
}


sub _update_volume {
	my($session, $volume) = @_;
	my $req = $session->request(
		"open-ils.storage.direct.asset.call_number.update",
		$volume );
	my $status = $req->gather(1);
}

sub _add_volume {

	my($session, $volume) = @_;

	my $request = $session->request( 
		"open-ils.storage.direct.asset.call_number.create", $volume );

	my $id = $request->gather(1);

	if( $id == 0 ) {
		OpenILS::Application::AppUtils->rollback_db_session($session);
		throw OpenSRF::EX::ERROR (" * -> Error creating new volume");
	}

	$volume->id($id);
	warn "received new volume id: $id\n";
	return $volume;

}




__PACKAGE__->register_method(
	method	=> "fleshed_copy_update",
	api_name	=> "open-ils.cat.asset.copy.fleshed.batch.update",
);

sub fleshed_copy_update {
	my($self, $client, $user_session, $copies) = @_;

	my $user_obj = $apputils->check_user_session($user_session); 
	my $session = $apputils->start_db_session();

	for my $copy (@$copies) {
		_fleshed_copy_update($session, $copy, $user_obj->id);
	}

	$apputils->commit_db_session($session);
	return 1;
}



sub _delete_copy {
	my($session, $copy) = @_;
	warn "Deleting copy " . $copy->id . "\n";
	my $request = $session->request(
		"open-ils.storage.direct.asset.copy.delete",
		$copy );
	return $request->gather(1);
}

sub _create_copy {
	my($session, $copy) = @_;

	my $request = $session->request(
		"open-ils.storage.direct.asset.copy.create",
		$copy );
	my $id = $request->gather(1);

	if($id < 1) {
		throw OpenSRF::EX::ERROR
			("Unable to create new copy " . Dumper($copy));
	}
	$copy->id($id);
	warn "Created copy " . $copy->id . "\n";

	return $copy;

}

sub _update_copy {
	my($session, $copy) = @_;
	my $request = $session->request(
		"open-ils.storage.direct.asset.copy.update", $copy );
	my $status = $request->gather(1);
	warn "Updated copy " . $copy->id . "\n";
	return $status;
}


# -----------------------------------------------------------------
# Creates/Updates/Deletes a fleshed asset.copy.  
# adds/deletes copy stat_cat maps where necessary
# -----------------------------------------------------------------
sub _fleshed_copy_update {
	my($session, $copy, $editor) = @_;

	my $stat_cat_entries = $copy->stat_cat_entries;
	$copy->editor($editor);
	
	# in case we're fleshed
	if(ref($copy->status))		{$copy->status( $copy->status->id ); }
	if(ref($copy->location))	{$copy->location( $copy->location->id ); }
	if(ref($copy->circ_lib))	{$copy->circ_lib( $copy->circ_lib->id ); }

	warn "Updating copy " . Dumper($copy) . "\n";

	if( $copy->isdeleted ) { 
		return _delete_copy($session, $copy);
	} elsif( $copy->isnew ) {
		$copy = _create_copy($session, $copy);
	} elsif( $copy->ischanged ) {
		_update_copy($session, $copy);
	}

	
	if(!@$stat_cat_entries) { return 1; }

	my $stat_maps = $session->request(
		"open-ils.storage.direct.asset.stat_cat_entry_copy_map.search.owning_copy",
		$copy->id )->gather(1);

	if(!$copy->isnew) { _delete_stale_maps($session, $stat_maps, $copy); }
	
	# go through the stat cat update/create process
	for my $stat_entry (@{$stat_cat_entries}){ 
		_copy_update_stat_cats( $session, $copy, $stat_maps, $stat_entry );
	}
	
	return 1;
}


# -----------------------------------------------------------------
# Deletes stat maps attached to this copy in the database that
# are no longer attached to the current copy
# -----------------------------------------------------------------
sub _delete_stale_maps {
	my( $session, $stat_maps, $copy) = @_;

	warn "Deleting stale stat maps for copy " . $copy->id . "\n";
	for my $map (@$stat_maps) {
	# if there is no stat cat entry on the copy who's id matches the
	# current map's id, remove the map from the database
	if(! grep { $_->id == $map->stat_cat_entry } @{$copy->stat_cat_entries} ) {
		my $req = $session->request(
			"open-ils.storage.direct.asset.stat_cat_entry_copy_map.delete", $map );
		$req->gather(1);
		}
	}

	return $stat_maps;
}


# -----------------------------------------------------------------
# Searches the stat maps to see if '$entry' already exists on
# the given copy.  If it does not, a new stat map is created
# for the given entry and copy
# -----------------------------------------------------------------
sub _copy_update_stat_cats {
	my ( $session, $copy, $stat_maps, $entry ) = @_;

	warn "Updating stat maps for copy " . $copy->id . "\n";

	# see if this map already exists
	for my $map (@$stat_maps) {
		if( $map->stat_cat_entry == $entry->id ) {return;}
	}

	warn "Creating new stat map for stat  " . 
		$entry->stat_cat . " and copy " . $copy->id . "\n";

	# if not, create it
	my $new_map = Fieldmapper::asset::stat_cat_entry_copy_map->new();

	$new_map->stat_cat( $entry->stat_cat );
	$new_map->stat_cat_entry( $entry->id );
	$new_map->owning_copy( $copy->id );

	warn "New map is " . Dumper($new_map) . "\n";

	my $request = $session->request(
		"open-ils.storage.direct.asset.stat_cat_entry_copy_map.create",
		$new_map );
	my $status = $request->gather(1);
	warn "created new map with id $status\n";

}




1;
