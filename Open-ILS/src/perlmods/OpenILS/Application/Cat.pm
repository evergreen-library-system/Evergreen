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
use OpenILS::Utils::Editor q/:funcs/;
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
	method	=> "biblio_record_replace_marc",
	api_name	=> "open-ils.cat.biblio.record.xml.update",
	argc		=> 3, 
	signature	=> q/
		Updates the XML for a given biblio record.
		This does not change any other aspect of the record entry
		exception the XML, the editor, and the edit date.
		@return The update record object
	/
);

__PACKAGE__->register_method(
	method		=> 'biblio_record_replace_marc',
	api_name		=> 'open-ils.cat.biblio.record.marc.replace',
	signature	=> q/
		@param auth The authtoken
		@param recid The record whose MARC we're replacing
		@param newxml The new xml to use
	/
);

__PACKAGE__->register_method(
	method		=> 'biblio_record_replace_marc',
	api_name		=> 'open-ils.cat.biblio.record.marc.replace.override',
	signature	=> q/@see open-ils.cat.biblio.record.marc.replace/
);

sub biblio_record_replace_marc  {
	my( $self, $conn, $auth, $recid, $newxml, $source ) = @_;

	my $e = new_editor(authtoken => $auth, xact => 1);

	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('CREATE_MARC');

	my $rec = $e->retrieve_biblio_record_entry($recid)
		or return $e->event;

	my $fixtcn = 1 if $self->api_name =~ /replace/o;

	# See if there is a different record in the database that has our TCN value
	# If we're not updating the TCN, all we care about it the marcdoc
	my $override = $self->api_name =~ /override/;

	my( $tcn, $tsource, $marcdoc, $evt) = 
		_find_tcn_info($e->session, $newxml, $override, $recid);

	return $evt if $evt;

	if( $fixtcn ) {
		$rec->tcn_value($tcn);
		$rec->tcn_source($tsource);
	}

	# XXX Make the source the ID from config.bib_source
	$rec->source($source) if ($source);
	$rec->editor($e->requestor->id);
	$rec->edit_date('now');
	$rec->marc( entityize( $marcdoc->documentElement->toString ) );

	$logger->activity("user ".$e->requestor->id." replacing MARC for record $recid");

	$e->update_biblio_record_entry($rec) or return $e->event;
	$e->request('open-ils.worm.wormize.biblio', $recid) or return $e->event;
	$e->commit;

	return $rec;
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


	# XXX Make the source the ID from config.bib_source

	my $override = 1 if $self->api_name =~ /override/;

	my( $tcn, $tcn_source, $marcdoc );
	my( $requestor, $evt ) = $U->checksesperm($authtoken, 'IMPORT_MARC');
	return $evt if $evt;

	my $session = $apputils->start_db_session();

	( $tcn, $tcn_source, $marcdoc, $evt ) = _find_tcn_info($session, $xml, $override);
	return $evt if $evt;

	$logger->activity("user ".$requestor->id.
		" creating new biblio entry with tcn=$tcn and tcn_source $tcn_source");

	my $record = Fieldmapper::biblio::record_entry->new;

	$record->source($source) if ($source);
	$record->tcn_source($tcn_source);
	$record->tcn_value($tcn);
	$record->creator($requestor->id);
	$record->editor($requestor->id);
	$record->create_date('now');
	$record->edit_date('now');
	$record->marc( entityize( $marcdoc->documentElement->toString ) );

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


sub _find_tcn_info { 
	my $session		= shift;
	my $xml			= shift;
	my $override	= shift;
	my $existing_rec	= shift || 0;

	# parse the XML
	my $marcxml = XML::LibXML->new->parse_string( $xml );
	$marcxml->documentElement->setNamespace( 
		"http://www.loc.gov/MARC21/slim", "marc", 1 );

	my $xpath = '//marc:controlfield[@tag="001"]';
	my $tcn = $marcxml->documentElement->findvalue($xpath);
	$logger->info("biblio import located 001 (tcn) value of $tcn");

	$xpath = '//marc:controlfield[@tag="003"]';
	my $tcn_source = $marcxml->documentElement->findvalue($xpath) || "System Local";

	if(my $rec = _tcn_exists($session, $tcn, $tcn_source, $existing_rec) ) {

		my $origtcn = $tcn;
		$tcn = find_free_tcn( $marcxml, $session, $existing_rec );

		# if we're overriding, try to find a different TCN to use
		if( $override ) {

			$logger->activity("tcn value $tcn already exists, attempting to override");

			if(!$tcn) {
				return ( 
					undef, 
					undef, 
					undef,
					OpenILS::Event->new(
						'OPEN_TCN_NOT_FOUND', 
							payload => $marcxml->toString())
					);
			}

		} else {

			$logger->warn("tcn value $origtcn already exists in import/create");

			# otherwise, return event
			return ( 
				undef, 
				undef, 
				undef,
				OpenILS::Event->new( 
					'TCN_EXISTS', payload => { 
						dup_record	=> $rec, 
						tcn			=> $origtcn,
						new_tcn		=> $tcn
						}
					)
				);
		}
	}

	return ($tcn, $tcn_source, $marcxml);
}

sub find_free_tcn {

	my $marcxml = shift;
	my $session = shift;
	my $existing_rec = shift;

	my $add_039 = 0;

	my $xpath = '//marc:datafield[@tag="039"]/subfield[@code="a"]';
	my ($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
	$xpath = '//marc:datafield[@tag="039"]/subfield[@code="b"]';
	my $tcn_source = $marcxml->documentElement->findvalue($xpath) || "System Local";

	if(_tcn_exists($session, $tcn, $tcn_source, $existing_rec)) {
		$tcn = undef;
	} else {
		$add_039++;
	}


	if(!$tcn) {
		$xpath = '//marc:datafield[@tag="020"]/subfield[@code="a"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "ISBN";
		if(_tcn_exists($session, $tcn, $tcn_source, $existing_rec)) {$tcn = undef;}
	}

	if(!$tcn) { 
		$xpath = '//marc:datafield[@tag="022"]/subfield[@code="a"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "ISSN";
		if(_tcn_exists($session, $tcn, $tcn_source, $existing_rec)) {$tcn = undef;}
	}

	if(!$tcn) {
		$xpath = '//marc:datafield[@tag="010"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "LCCN";
		if(_tcn_exists($session, $tcn, $tcn_source, $existing_rec)) {$tcn = undef;}
	}

	if(!$tcn) {
		$xpath = '//marc:datafield[@tag="035"]/subfield[@code="a"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "System Legacy";
		if(_tcn_exists($session, $tcn, $tcn_source, $existing_rec)) {$tcn = undef;}

		if($tcn) {
			$marcxml->documentElement->removeChild(
				$marcxml->documentElement->findnodes( '//datafield[@tag="035"]' )
			);
		}
	}

	return undef unless $tcn;

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
	my $existing_rec = shift || 0;

	if(!$tcn) {return 0;}

	$logger->debug("tcn_exists search for tcn $tcn and source $source and id $existing_rec");

	# XXX why does the source matter?
#	my $req = $session->request(      
#		{ tcn_value => $tcn, tcn_source => $source, deleted => 'f' } );

	my $req = $session->request(      
		"open-ils.storage.id_list.biblio.record_entry.search_where.atomic",
		{ tcn_value => $tcn, deleted => 'f', id => {'!=' => $existing_rec} } );

	my $recs = $req->gather(1);

	if($recs and $recs->[0]) {
		$logger->debug("_tcn_exists is true for tcn : $tcn ($source)");
		return $recs->[0];
	}

	$logger->debug("_tcn_exists is false for tcn : $tcn ($source)");
	return 0;
}




# XXX deprecated. Remove me.

=head deprecated

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
=cut


=head deprecate 
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

=cut



__PACKAGE__->register_method(
	method	=> "biblio_record_record_metadata",
	api_name	=> "open-ils.cat.biblio.record.metadata.retrieve",
	argc		=> 1, #(session_id, biblio_tree ) 
	notes		=> "Walks the tree and commits any changed nodes " .
					"adds any new nodes, and deletes any deleted nodes",
);

sub biblio_record_record_metadata {
	my( $self, $client, $authtoken, $ids ) = @_;

	return [] unless $ids and @$ids;

	my $editor = OpenILS::Utils::Editor->new(authtoken => $authtoken);
	return $editor->event unless $editor->checkauth;
	return $editor->event unless $editor->allowed('VIEW_USER');

	my @results;

	for(@$ids) {
		return $editor->event unless 
			my $rec = $editor->retrieve_biblio_record_entry($_);
		$rec->creator($editor->retrieve_actor_user($rec->creator));
		$rec->editor($editor->retrieve_actor_user($rec->editor));
		$rec->clear_marc; # slim the record down
		push( @results, $rec );
	}

	return \@results;
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


__PACKAGE__->register_method(
	method	=> "fleshed_copy_update",
	api_name	=> "open-ils.cat.asset.copy.fleshed.batch.update",);

__PACKAGE__->register_method(
	method	=> "fleshed_copy_update",
	api_name	=> "open-ils.cat.asset.copy.fleshed.batch.update.override",);

sub fleshed_copy_update {
	my( $self, $conn, $auth, $copies ) = @_;
	return 1 unless ref $copies;
	my( $reqr, $evt ) = $U->checkses($auth);
	return $evt if $evt;
	my $editor = OpenILS::Utils::Editor->new(requestor => $reqr, xact => 1);
	my $override = $self->api_name =~ /override/;
	$evt = update_fleshed_copies( $editor, $override, undef, $copies);
	return $evt if $evt;
	$editor->finish;
	$logger->info("fleshed copy update successfully updated ".scalar(@$copies)." copies");
	return 1;
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




# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# returns true if the given title (id) has no un-deleted
# copies attached
sub title_is_empty {
	my( $editor, $rid ) = @_;

	my $cnlist = $editor->search_asset_call_number(
		{ record => $rid, deleted => 'f' }, { idlist => 1 } );
	return 1 unless @$cnlist;

	for my $cn (@$cnlist) {
		my $copylist = $editor->search_asset_copy(
			{ call_number => $cn, deleted => 'f' }, { idlist => 1 });
		return 0 if @$copylist; # false if we find any copies
	}

	return 1;
}


__PACKAGE__->register_method(
	method	=> "fleshed_volume_update",
	api_name	=> "open-ils.cat.asset.volume.fleshed.batch.update",);

__PACKAGE__->register_method(
	method	=> "fleshed_volume_update",
	api_name	=> "open-ils.cat.asset.volume.fleshed.batch.update.override",);

sub fleshed_volume_update {
	my( $self, $conn, $auth, $volumes ) = @_;
	my( $reqr, $evt ) = $U->checkses($auth);
	return $evt if $evt;

	my $override = ($self->api_name =~ /override/);
	my $editor = OpenILS::Utils::Editor->new( requestor => $reqr, xact => 1 );

	for my $vol (@$volumes) {
		$logger->info("vol-update: investigating volume ".$vol->id);

		$vol->editor($reqr->id);
		$vol->edit_date('now');

		my $copies = $vol->copies;
		$vol->clear_copies;

		if( $vol->isdeleted ) {

			$logger->info("vol-update: deleting volume");
			my $cs = $editor->search_asset_copy(
				{ call_number => $vol->id, deleted => 'f' } );
			return OpenILS::Event->new(
				'VOLUME_NOT_EMPTY', payload => $vol->id ) if @$cs;

			$vol->deleted('t');
			return $editor->event unless
				$editor->update_asset_call_number($vol);

			
		} elsif( $vol->isnew ) {
			$logger->info("vol-update: creating volume");
			$evt = create_volume( $override, $editor, $vol );
			return $evt if $evt;

		} elsif( $vol->ischanged ) {
			$logger->info("vol-update: update volume");
			return $editor->event unless
				$editor->update_asset_call_number($vol);
			return $evt if $evt;
		}

		# now update any attached copies
		if( @$copies and !$vol->isdeleted ) {
			$_->call_number($vol->id) for @$copies;
			$evt = update_fleshed_copies( $editor, $override, $vol, $copies );
			return $evt if $evt;
		}
	}

	$editor->finish;
	return scalar(@$volumes);
}


# this does the actual work
sub update_fleshed_copies {
	my( $editor, $override, $vol, $copies ) = @_;

	my $evt;
	my $fetchvol = ($vol) ? 0 : 1;

	my %cache;
	$cache{$vol->id} = $vol if $vol;

	for my $copy (@$copies) {

		my $copyid = $copy->id;
		$logger->info("vol-update: inspecting copy $copyid");

		if( !($vol = $cache{$copy->call_number}) ) {
			$vol = $cache{$copy->call_number} = 
				$editor->retrieve_asset_call_number($copy->call_number);
			return $editor->event unless $vol;
		}

		$copy->editor($editor->requestor->id);
		$copy->edit_date('now');

		$copy->status( $copy->status->id ) if ref($copy->status);
		$copy->location( $copy->location->id ) if ref($copy->location);
		$copy->circ_lib( $copy->circ_lib->id ) if ref($copy->circ_lib);
		
		my $sc_entries = $copy->stat_cat_entries;
		$copy->clear_stat_cat_entries;

		if( $copy->isdeleted ) {
			$evt = delete_copy($editor, $override, $vol, $copy);
			return $evt if $evt;

		} elsif( $copy->isnew ) {
			$evt = create_copy( $editor, $vol, $copy );
			return $evt if $evt;

		} elsif( $copy->ischanged ) {

			$logger->info("vol-update: updating copy $copyid");
			return $editor->event unless
				$editor->update_asset_copy(
					$copy, {checkperm=>1, permorg=>$vol->owning_lib});
			return $evt if $evt;
		}

		$copy->stat_cat_entries( $sc_entries );
		$evt = update_copy_stat_entries($editor, $copy);
		return $evt if $evt;
	}

	$logger->debug("vol-update: done updating copy batch");

	return undef;
}

sub delete_copy {
	my( $editor, $override, $vol, $copy ) = @_;

	$logger->info("vol-update: deleting copy ".$copy->id);
	$copy->deleted('t');

	$editor->update_asset_copy(
		$copy, {checkperm=>1, permorg=>$vol->owning_lib})
		or return $editor->event;

	if( title_is_empty($editor, $vol->record) ) {

		if( $override ) {

			# delete this volume if it's not already marked as deleted
			if(!$vol->deleted || $vol->deleted =~ /f/io || ! $vol->isdeleted) {
				$vol->deleted('t');
				$editor->update_asset_call_number($vol, {checkperm=>0})
					or return $editor->event;
			}

			# then delete the record this volume points to
			my $rec = $editor->retrieve_biblio_record_entry($vol->record)
				or return $editor->event;

			if( !$rec->deleted ) {
				$rec->deleted('t');
				$rec->active('f');
				$editor->update_biblio_record_entry($rec, {checkperm=>0})
					or return $editor->event;
			}

		} else {
			return OpenILS::Event->new('TITLE_LAST_COPY');
		}
	}

	return undef;
}

sub create_copy {
	my( $editor, $vol, $copy ) = @_;

	my $existing = $editor->search_asset_copy(
		{ barcode => $copy->barcode } );
	
	return OpenILS::Event->new('ITEM_BARCODE_EXISTS') if @$existing;

	$copy->clear_id;
	$copy->creator($editor->requestor->id);
	$copy->create_date('now');

	$editor->create_asset_copy(
		$copy, {checkperm=>1, permorg=>$vol->owning_lib})
		or return $editor->event;

	return undef;
}

sub update_copy_stat_entries {
	my( $editor, $copy ) = @_;

	my $evt;
	my $entries = $copy->stat_cat_entries;
	return undef unless ($entries and @$entries);

	my $maps = $editor->search_asset_stat_cat_entry_copy_map({owning_copy=>$copy->id});

	if(!$copy->isnew) {
		# if there is no stat cat entry on the copy who's id matches the
		# current map's id, remove the map from the database
		for my $map (@$maps) {
			if(! grep { $_->id == $map->stat_cat_entry } @$entries ) {

				$logger->info("copy update found stale ".
					"stat cat entry map ".$map->id. " on copy ".$copy->id);

				$editor->delete_asset_stat_cat_entry_copy_map($map)
					or return $editor->event;
			}
		}
	}
	
	# go through the stat cat update/create process
	for my $entry (@$entries) { 

		# if this link already exists in the DB, don't attempt to re-create it
		next if( grep{$_->stat_cat_entry == $entry->id} @$maps );
	
		my $new_map = Fieldmapper::asset::stat_cat_entry_copy_map->new();
		
		$new_map->stat_cat( $entry->stat_cat );
		$new_map->stat_cat_entry( $entry->id );
		$new_map->owning_copy( $copy->id );

		$editor->create_asset_stat_cat_entry_copy_map($new_map)
			or return $editor->event;

		$logger->info("copy update created new stat cat entry map ".$editor->data);
	}

	return undef;
}


sub create_volume {
	my( $override, $editor, $vol ) = @_;
	my $evt;


	# first lets see if there are any collisions
	my $vols = $editor->search_asset_call_number( { 
			owning_lib	=> $vol->owning_lib,
			record		=> $vol->record,
			label			=> $vol->label,
			deleted		=> 'f'
		}
	);

	my $label = undef;
	if(@$vols) {
		if($override) { 
			$label = $vol->label;
		} else {
			return OpenILS::Event->new(
				'VOLUME_LABEL_EXISTS', payload => $vol->id);
		}
	}

	# create a temp label so we can create the volume, then de-dup it
	$vol->label( '__SYSTEM_TMP_'.time) if $label;

	$vol->creator($editor->requestor->id);
	$vol->create_date('now');
	$vol->clear_id;

	$editor->create_asset_call_number($vol) or return $editor->event;

	if($label) {
		# now restore the label and merge into the existing record
		$vol->label($label);
		(undef, $evt) = 
			OpenILS::Application::Cat::Merge::merge_volumes($editor, [$vol], $$vols[0]);
		return $evt if $evt;
	}

	return undef;
}






1;
