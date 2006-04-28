use strict; use warnings;
package OpenILS::Application::Cat;
use OpenILS::Application::AppUtils;
use OpenSRF::Application;
use OpenILS::Application::Cat::Utils;
use OpenILS::Application::Cat::Merge;
use base qw/OpenSRF::Application/;
use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;

use XML::LibXML;
use Unicode::Normalize;
use Data::Dumper;
use OpenILS::Utils::FlatXML;
use OpenILS::Utils::Editor;
use OpenILS::Perm;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw($logger);

my $apputils = "OpenILS::Application::AppUtils";

my $utils = "OpenILS::Application::Cat::Utils";
my $U = "OpenILS::Application::AppUtils";

my $conf;

my %marctemplates;

sub entityize { 
	my $stuff = shift;
	my $form = shift || "";

	if ($form eq 'D') {
		$stuff = NFD($stuff);
	} else {
		$stuff = NFC($stuff);
	}

	$stuff =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
	return $stuff;
}

__PACKAGE__->register_method(
	method	=> "retrieve_marc_template",
	api_name	=> "open-ils.cat.biblio.marc_template.retrieve",
	notes		=> <<"	NOTES");
	Returns a MARC 'record tree' based on a set of pre-defined templates.
	Templates include : book
	NOTES

sub retrieve_marc_template {
	my( $self, $client, $type ) = @_;

	return $marctemplates{$type} if defined($marctemplates{$type});
	$marctemplates{$type} = _load_marc_template($type);
	return $marctemplates{$type};
}

sub _load_marc_template {
	my $type = shift;

	if(!$conf) { $conf = OpenSRF::Utils::SettingsClient->new; }

	my $template = $conf->config_value(					
		"apps", "open-ils.cat","app_settings", "marctemplates", $type );
	warn "Opening template file $template\n";

	open( F, $template ) or 
		throw OpenSRF::EX::ERROR ("Unable to open MARC template file: $template : $@");

	my @xml = <F>;
	close(F);
	my $xml = join('', @xml);

	return XML::LibXML->new->parse_string($xml)->documentElement->toString;
}



__PACKAGE__->register_method(
	method	=> "create_record_xml",
	api_name	=> "open-ils.cat.biblio.record.xml.create.override",
	signature	=> q/@see open-ils.cat.biblio.record.xml.create/);

__PACKAGE__->register_method(
	method		=> "create_record_xml",
	api_name		=> "open-ils.cat.biblio.record.xml.create",
	signature	=> q/
		Inserts a new biblio with the given XML
	/
);

sub create_record_xml {
	my( $self, $client, $login, $xml, $source ) = @_;
	$source ||= 2;

	my $override = 1 if $self->api_name =~ /override/;

	my( $user_obj, $evt ) = $U->checksesperm($login, 'CREATE_MARC');
	return $evt if $evt;

	$logger->activity("user ".$user_obj->id." creating new MARC record");

	my $meth = $self->method_lookup("open-ils.cat.biblio.record.xml.import");

	$meth = $self->method_lookup(
		"open-ils.cat.biblio.record.xml.import.override") if $override;

	my ($s) = $meth->run($login, $xml, 2);
	return $s;
}




__PACKAGE__->register_method(
	method	=> "biblio_record_xml_import",
	api_name	=> "open-ils.cat.biblio.record.xml.import.override",
	signature	=> q/@see open-ils.cat.biblio.record.xml.import/);

__PACKAGE__->register_method(
	method	=> "biblio_record_xml_import",
	api_name	=> "open-ils.cat.biblio.record.xml.import",
	notes		=> <<"	NOTES");
	Takes a marcxml record and imports the record into the database.  In this
	case, the marcxml record is assumed to be a complete record (i.e. valid
	MARC).  The title control number is taken from (whichever comes first)
	tags 001, 039[ab], 020a, 022a, 010, 035a and whichever does not already exist
	in the database.
	user_session must have IMPORT_MARC permissions
	NOTES


sub biblio_record_xml_import {
	my( $self, $client, $authtoken, $xml, $source) = @_;

	my ($tcn, $tcn_source);

	my $override = 1 if $self->api_name =~ /override/;

	my( $requestor, $evt ) = $U->checksesperm($authtoken, 'IMPORT_MARC');
	return $evt if $evt;

	my $session = $apputils->start_db_session();

	# parse the XML
	my $marcxml = XML::LibXML->new->parse_string( $xml );
	$marcxml->documentElement->setNamespace( 
		"http://www.loc.gov/MARC21/slim", "marc", 1 );

	my $xpath = '//marc:controlfield[@tag="001"]';
	$tcn = $marcxml->documentElement->findvalue($xpath);
	$logger->info("biblio import located 001 (tcn) value of $tcn");

	$xpath = '//marc:controlfield[@tag="003"]';
	$tcn_source = $marcxml->documentElement->findvalue($xpath) || "System Local";

	if(my $rec = _tcn_exists($session, $tcn, $tcn_source)) {

		my $origtcn = $tcn;
		$tcn = find_free_tcn( $marcxml, $session );

		# if we're overriding, try to find a different TCN to use
		if( $override ) {

			$logger->activity("tcn value $tcn already exists, attempting to override");

			if(!$tcn) {
				return OpenILS::Event->new(
					'OPEN_TCN_NOT_FOUND', payload => $marcxml->toString());
			}

		} else {

			$logger->warn("tcn value $origtcn already exists in import/create");

			# otherwise, return event
			return OpenILS::Event->new( 
				'TCN_EXISTS', payload => { 
					dup_record	=> $rec, 
					tcn			=> $origtcn,
					new_tcn		=> $tcn
					} );
		}

	} else {

		$logger->activity("user ".$requestor->id.
		" creating new biblio entry with tcn=$tcn and tcn_source $tcn_source");
	}


	my $record = Fieldmapper::biblio::record_entry->new;

	$record->source($source) if ($source);
	$record->tcn_source($tcn_source);
	$record->tcn_value($tcn);
	$record->creator($requestor->id);
	$record->editor($requestor->id);
	$record->marc( entityize( $marcxml->documentElement->toString ) );

	my $id = $session->request(
		"open-ils.storage.direct.biblio.record_entry.create", $record )->gather(1);

	return $U->DB_UPDATE_FAILED($record) unless $id;
	$record->id( $id );

	$logger->info("marc create/import created new record $id");

	$apputils->commit_db_session($session);

	$logger->debug("Sending record off to be wormized");

	my $stat = $U->storagereq( 'open-ils.worm.wormize.biblio', $id );
	throw OpenSRF::EX::ERROR 
		("Unable to wormize imported record") unless $stat;

	return $record;
}

sub find_free_tcn {

	my $marcxml = shift;
	my $session = shift;

	my $add_039 = 0;

	my $xpath = '//marc:datafield[@tag="039"]/subfield[@code="a"]';
	my ($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
	$xpath = '//marc:datafield[@tag="039"]/subfield[@code="b"]';
	my $tcn_source = $marcxml->documentElement->findvalue($xpath) || "System Local";

	if(_tcn_exists($session, $tcn, $tcn_source)) {
		$tcn = undef;
	} else {
		$add_039++;
	}


	if(!$tcn) {
		$xpath = '//marc:datafield[@tag="020"]/subfield[@code="a"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "ISBN";
		if(_tcn_exists($session, $tcn, $tcn_source)) {$tcn = undef;}
	}

	if(!$tcn) { 
		$xpath = '//marc:datafield[@tag="022"]/subfield[@code="a"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "ISSN";
		if(_tcn_exists($session, $tcn, $tcn_source)) {$tcn = undef;}
	}

	if(!$tcn) {
		$xpath = '//marc:datafield[@tag="010"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "LCCN";
		if(_tcn_exists($session, $tcn, $tcn_source)) {$tcn = undef;}
	}

	if(!$tcn) {
		$xpath = '//marc:datafield[@tag="035"]/subfield[@code="a"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "System Legacy";
		if(_tcn_exists($session, $tcn, $tcn_source)) {$tcn = undef;}

		if($tcn) {
			$marcxml->documentElement->removeChild(
				$marcxml->documentElement->findnodes( '//datafield[@tag="035"]' )
			);
		}
	}

	if ($add_039) {
		my $df = $marcxml->createElementNS( 'http://www.loc.gov/MARC21/slim', 'datafield');
		$df->setAttribute( tag => '039' );
		$df->setAttribute( ind1 => ' ' );
		$df->setAttribute( ind2 => ' ' );
		$marcxml->documentElement->appendChild( $df );

		my $sfa = $marcxml->createElementNS( 'http://www.loc.gov/MARC21/slim', 'subfield');
		$sfa->setAttribute( code => 'a' );
		$sfa->appendChild( $marcxml->createTextNode( $tcn ) );
		$df->appendChild( $sfa );

		my $sfb = $marcxml->createElementNS( 'http://www.loc.gov/MARC21/slim', 'subfield');
		$sfb->setAttribute( code => 'b' );
		$sfb->appendChild( $marcxml->createTextNode( $tcn_source ) );
		$df->appendChild( $sfb );
	}

	return $tcn;
}



sub _tcn_exists {
	my $session = shift;
	my $tcn = shift;
	my $source = shift;

	if(!$tcn) {return 0;}

	$logger->debug("tcn_exists search for tcn $tcn and source $source");

	my $req = $session->request(      
		"open-ils.storage.id_list.biblio.record_entry.search_where.atomic",
		{ tcn_value => $tcn, tcn_source => $source, deleted => 'f' } );

	my $recs = $req->gather(1);

	if($recs and $recs->[0]) {
		$logger->debug("_tcn_exists is true for tcn : $tcn ($source)");
		return $recs->[0];
	}

	$logger->debug("_tcn_exists is false for tcn : $tcn ($source)");
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
	method	=> "biblio_record_xml_update",
	api_name	=> "open-ils.cat.biblio.record.xml.update",
	argc		=> 3, #(session_id, biblio_tree ) 
	notes		=> <<'	NOTES');
	Updates the XML of a biblio record entry
	@param authtoken The session token for the staff updating the record
	@param docID The record entry ID to update
	@param xml The new MARCXML record
	NOTES

sub biblio_record_xml_update {

	my( $self, $client, $user_session,  $id, $xml ) = @_;

	my $user_obj = $apputils->check_user_session($user_session); 

	if($apputils->check_user_perms(
			$user_obj->id, $user_obj->home_ou, "UPDATE_MARC")) {
		return OpenILS::Perm->new("UPDATE_MARC"); 
	}

	$logger->activity("user ".$user_obj->id." updating biblio record $id");


	my $session = OpenILS::Application::AppUtils->start_db_session();

	warn "Retrieving biblio record from storage for update\n";

	my $req1 = $session->request(
			"open-ils.storage.direct.biblio.record_entry.batch.retrieve", $id );
	my $biblio = $req1->gather(1);

	warn "retrieved doc $id\n";

	my $doc = XML::LibXML->new->parse_string($xml);
	throw OpenSRF::EX::ERROR ("Invalid XML in record update: $xml") unless $doc;

	$biblio->marc( entityize( $doc->documentElement->toString ) );
	$biblio->editor( $user_obj->id );
	$biblio->edit_date( 'now' );

	warn "Sending updated doc $id to db with xml ".$biblio->marc. "\n";

	my $req = $session->request( 
		"open-ils.storage.direct.biblio.record_entry.update", $biblio );

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

	my $wreq = $session->request( "open-ils.worm.wormize.biblio", $id );

	my $w = 0;
	try {
		$w = $wreq->gather(1);

	} catch Error with {
		my $e = shift;
		warn "wormizing failed, rolling back\n";
		OpenILS::Application::AppUtils->rollback_db_session($session);

		if($e) { throw $e ($e); }
		throw OpenSRF::EX::ERROR ("Wormizing Failed for $id" );
	};

	warn "Committing db session...\n";
	OpenILS::Application::AppUtils->commit_db_session( $session );

#	$client->respond_complete($tree);

	warn "Done wormizing\n";

	#use Data::Dumper;
	#warn "Returning tree:\n";
	#warn Dumper $tree;

	return $biblio;

}



__PACKAGE__->register_method(
	method	=> "biblio_record_record_metadata",
	api_name	=> "open-ils.cat.biblio.record.metadata.retrieve",
	argc		=> 1, #(session_id, biblio_tree ) 
	notes		=> "Walks the tree and commits any changed nodes " .
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

		$record_entry->creator($creator);
		$record_entry->editor($editor);

		push @$results, $record_entry;

	}

	$request->finish;
	$session->disconnect();
	$session->finish();

	return $results;

}

__PACKAGE__->register_method(
	method	=> "biblio_record_marc_cn",
	api_name	=> "open-ils.cat.biblio.record.marc_cn.retrieve",
	argc		=> 1, #(bib id ) 
);

sub biblio_record_marc_cn {
	my( $self, $client, $id ) = @_;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $marc = $session
		->request("open-ils.storage.direct.biblio.record_entry.retrieve", $id )
		->gather(1)
		->marc;

	my $doc = XML::LibXML->new->parse_string($marc);
	$doc->documentElement->setNamespace( "http://www.loc.gov/MARC21/slim", "marc", 1 );
	
	my @res;
	for my $tag ( qw/050 055 060 070 080 082 086 088 090 092 096 098 099/ ) {
		my @node = $doc->findnodes("//marc:datafield[\@tag='$tag']");
		for my $x (@node) {
			my $cn = $x->findvalue("marc:subfield[\@code='a' or \@code='b']");
			push @res, {$tag => $cn} if ($cn);
		}
	}

	return \@res
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
		"open-ils.storage.direct.actor.user.search.usrname.atomic", @users );

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
		"open-ils.storage.direct.asset.call_number.search_where.atomic",
		{ record => $record_id, deleted => 'f' });
		#"open-ils.storage.direct.asset.call_number.search.record.atomic",

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

	$search_hash->{deleted} = 'f';

	my	$session = OpenSRF::AppSession->create( "open-ils.storage" );
	

	my $request = $session->request( 
			"open-ils.storage.direct.asset.call_number.search.atomic", $search_hash );
			#"open-ils.storage.direct.asset.call_number.search.atomic", $search_hash );

	my $vols = $request->gather(1);
	my @volumes;

	for my $volume (@$vols) {

		warn "Grabbing copies for volume: " . $volume->id . "\n";
		my $creq = $session->request(
			"open-ils.storage.direct.asset.copy.search_where.atomic", 
			{ call_number => $volume->id , deleted => 'f' });
			#"open-ils.storage.direct.asset.copy.search.call_number.atomic", $volume->id );

		my $copies = $creq->gather(1);

		$copies = [ sort { $a->barcode cmp $b->barcode } @$copies  ];

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
			my $status = _delete_volume($session, $volume, $user_obj);
			#if(!$status) {
				#throw OpenSRF::EX::ERROR
					#("Volume delete failed for volume " . $volume->id);
			#}
			if(UNIVERSAL::isa($status, "Fieldmapper::perm_ex")) { return $status; }

		} elsif( $volume->isnew ) {

			$volume->clear_id;
			$volume->editor($user_obj->id);
			$volume->creator($user_obj->id);
			$volume = _add_volume($session, $volume, $user_obj);
			use Data::Dumper;
			warn Dumper $volume;
			if($volume and UNIVERSAL::isa($volume, "Fieldmapper::perm_ex")) { return $volume; }

		} elsif( $volume->ischanged ) {

			$volume->editor($user_obj->id);
			my $stat = _update_volume($session, $volume, $user_obj);
			if($stat and UNIVERSAL::isa($stat, "Fieldmapper::perm_ex")) { return $stat; }
		}


		if( ! $volume->isdeleted ) {
			for my $copy (@{$update_copy_list}) {
	
				$copy->editor($user_obj->id);
				warn "updating copy for volume " . $volume->id . "\n";
	
				if( $copy->isnew ) {
	
					$copy->clear_id;
					$copy->call_number($volume->id);
					$copy->creator($user_obj->id);
					$copy = _fleshed_copy_update($session,$copy,$user_obj);
	
				} elsif( $copy->ischanged ) {
					$copy->call_number($volume->id);
					$copy = _fleshed_copy_update($session, $copy, $user_obj);
	
				} elsif( $copy->isdeleted ) {
					warn "Deleting copy " . $copy->id . " for volume " . $volume->id . "\n";
					my $status = _fleshed_copy_update($session, $copy, $user_obj);
					warn "Copy delete returned a status of $status\n";
				}
			}
		}
	}

	$apputils->commit_db_session($session);
	return scalar(@$volumes);
}


sub _delete_volume {
	my( $session, $volume, $user_obj ) = @_;

	if($apputils->check_user_perms(
			$user_obj->id, $user_obj->home_ou, "DELETE_VOLUME")) {
		return OpenILS::Perm->new("DELETE_VOLUME"); }

	#$volume = _find_volume($session, $volume);
	warn "Deleting volume " . $volume->id . "\n";

	my $copies = $session->request(
		"open-ils.storage.direct.asset.copy.search_where.atomic", 
		{ call_number => $volume->id, deleted => 'f' } )->gather(1);
		#"open-ils.storage.direct.asset.copy.search.call_number.atomic",

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
	my($session, $volume, $user_obj) = @_;
	if($apputils->check_user_perms(
			$user_obj->id, $user_obj->home_ou, "UPDATE_VOLUME")) {
		return OpenILS::Perm->new("UPDATE_VOLUME"); }

	my $req = $session->request(
		"open-ils.storage.direct.asset.call_number.update",
		$volume );
	my $status = $req->gather(1);
}

sub _add_volume {

	my($session, $volume, $user_obj) = @_;

	if($apputils->check_user_perms(
			$user_obj->id, $user_obj->home_ou, "CREATE_VOLUME")) {
		warn "User does not have priveleges to create new volumes\n";
		return OpenILS::Perm->new("CREATE_VOLUME"); 
	}

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
		_fleshed_copy_update($session, $copy, $user_obj);
	}

	$apputils->commit_db_session($session);
	return 1;
}



sub _delete_copy {
	my($session, $copy, $user_obj) = @_;

	if($apputils->check_user_perms(
			$user_obj->id, $user_obj->home_ou, "DELETE_COPY")) {
		return OpenILS::Perm->new("DELETE_COPY"); }

	warn "Deleting copy " . $copy->id . "\n";
	my $request = $session->request(
		"open-ils.storage.direct.asset.copy.delete",
		$copy );
	return $request->gather(1);
}

sub _create_copy {
	my($session, $copy, $user_obj) = @_;

	if($apputils->check_user_perms(
			$user_obj->id, $user_obj->home_ou, "CREATE_COPY")) {
		return OpenILS::Perm->new("CREATE_COPY"); }

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
	my($session, $copy, $user_obj) = @_;

	my $evt = $apputils->check_perms($user_obj->id, $copy->circ_lib, 'UPDATE_COPY');
	return $evt if $evt; #XXX NOT YET HANDLED BY CALLER

	my $status = $apputils->simplereq( 	
		'open-ils.storage',
		"open-ils.storage.direct.asset.copy.update", $copy );
	$logger->debug("Successfully updated copy " . $copy->id );
	return $status;
}


# -----------------------------------------------------------------
# Creates/Updates/Deletes a fleshed asset.copy.  
# adds/deletes copy stat_cat maps where necessary
# -----------------------------------------------------------------
sub _fleshed_copy_update {
	my($session, $copy, $editor) = @_;

	my $stat_cat_entries = $copy->stat_cat_entries;
	$copy->editor($editor->id);
	
	# in case we're fleshed
	if(ref($copy->status))		{$copy->status( $copy->status->id ); }
	if(ref($copy->location))	{$copy->location( $copy->location->id ); }
	if(ref($copy->circ_lib))	{$copy->circ_lib( $copy->circ_lib->id ); }

	warn "Updating copy " . Dumper($copy) . "\n";

	if( $copy->isdeleted ) { 
		return _delete_copy($session, $copy, $editor);
	} elsif( $copy->isnew ) {
		$copy = _create_copy($session, $copy, $editor);
	} elsif( $copy->ischanged ) {
		_update_copy($session, $copy, $editor);
	}

	
	return 1 unless ( $stat_cat_entries and @$stat_cat_entries );

	my $stat_maps = $session->request(
		"open-ils.storage.direct.asset.stat_cat_entry_copy_map.search.owning_copy.atomic",
		$copy->id )->gather(1);

	if(!$copy->isnew) { _delete_stale_maps($session, $stat_maps, $copy); }
	
	# go through the stat cat update/create process
	for my $stat_entry (@{$stat_cat_entries}){ 
		_copy_update_stat_cats( $session, $copy, $stat_maps, $stat_entry, $editor );
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
	my ( $session, $copy, $stat_maps, $entry, $editor ) = @_;

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


__PACKAGE__->register_method(
	method => 'merge',
	api_name	=> 'open-ils.cat.biblio.records.merge',
	signature	=> q/
		Merges a group of records
		@param auth The login session key
		@param master The id of the record all other r
			ecords should be merged into
		@param records Array of records to be merged into the master record
		@return 1 on success, Event on error.
	/
);

sub merge {
	my( $self, $conn, $auth, $master, $records ) = @_;
	my( $reqr, $evt ) = $U->checkses($auth);
	return $evt if $evt;
	my $editor = OpenILS::Utils::Editor->new( requestor => $reqr, xact => 1 );
	my $v = OpenILS::Application::Cat::Merge::merge_records($editor, $master, $records);
	return $v if $v;
	$editor->finish;
	return 1;
}



1;
