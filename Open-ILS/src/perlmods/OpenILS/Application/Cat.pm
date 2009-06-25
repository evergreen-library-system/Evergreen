use strict; use warnings;
package OpenILS::Application::Cat;
use OpenILS::Application::AppUtils;
use OpenILS::Application;
use OpenILS::Application::Cat::Merge;
use OpenILS::Application::Cat::Authority;
use OpenILS::Application::Cat::BibCommon;
use OpenILS::Application::Cat::AssetCommon;
use base qw/OpenILS::Application/;
use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;
use OpenILS::Const qw/:const/;

use XML::LibXML;
use Unicode::Normalize;
use Data::Dumper;
use OpenILS::Utils::FlatXML;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Perm;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw($logger);
use OpenSRF::AppSession;

my $U = "OpenILS::Application::AppUtils";
my $conf;
my %marctemplates;

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

__PACKAGE__->register_method(
	method => 'fetch_marc_template_types',
	api_name => 'open-ils.cat.marc_template.types.retrieve'
);

my $marc_template_files;

sub fetch_marc_template_types {
	my( $self, $conn ) = @_;
	__load_marc_templates();
	return [ keys %$marc_template_files ];
}

sub __load_marc_templates {
	return if $marc_template_files;
	if(!$conf) { $conf = OpenSRF::Utils::SettingsClient->new; }

	$marc_template_files = $conf->config_value(					
		"apps", "open-ils.cat","app_settings", "marctemplates" );

	$logger->info("Loaded marc templates: " . Dumper($marc_template_files));
}

sub _load_marc_template {
	my $type = shift;

	__load_marc_templates();

	my $template = $$marc_template_files{$type};
	open( F, $template ) or 
		throw OpenSRF::EX::ERROR ("Unable to open MARC template file: $template : $@");

	my @xml = <F>;
	close(F);
	my $xml = join('', @xml);

	return XML::LibXML->new->parse_string($xml)->documentElement->toString;
}



__PACKAGE__->register_method(
	method => 'fetch_bib_sources',
	api_name => 'open-ils.cat.bib_sources.retrieve.all');

sub fetch_bib_sources {
	return OpenILS::Application::Cat::BibCommon->fetch_bib_sources();
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

	my $override = 1 if $self->api_name =~ /override/;

	my( $user_obj, $evt ) = $U->checksesperm($login, 'CREATE_MARC');
	return $evt if $evt;

	$logger->activity("user ".$user_obj->id." creating new MARC record");

	my $meth = $self->method_lookup("open-ils.cat.biblio.record.xml.import");

	$meth = $self->method_lookup(
		"open-ils.cat.biblio.record.xml.import.override") if $override;

	my ($s) = $meth->run($login, $xml, $source);
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
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('CREATE_MARC', $e->requestor->ws_ou);

    my $no_ingest = 1;
    my $fix_tcn = $self->api_name =~ /replace/o;
    my $override = $self->api_name =~ /override/o;

    my $res = OpenILS::Application::Cat::BibCommon->biblio_record_replace_marc(
        $e, $recid, $newxml, $source, $fix_tcn, $override, $no_ingest);

    $e->commit unless $U->event_code($res);

    my $ses = OpenSRF::AppSession->create('open-ils.ingest');
    $ses->request('open-ils.ingest.full.biblio.record', $recid);

    return $res;
}

__PACKAGE__->register_method(
	method	=> "update_biblio_record_entry",
	api_name	=> "open-ils.cat.biblio.record_entry.update",
    signature => q/
        Updates a biblio.record_entry
        @param auth The authtoken
        @param record The record with updated values
        @return 1 on success, Event on error.
    /
);

sub update_biblio_record_entry {
    my($self, $conn, $auth, $record) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('UPDATE_RECORD');
    $e->update_biblio_record_entry($record) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method	=> "undelete_biblio_record_entry",
	api_name	=> "open-ils.cat.biblio.record_entry.undelete",
    signature => q/
        Un-deletes a record and sets active=true
        @param auth The authtoken
        @param record The record_id to ressurect
        @return 1 on success, Event on error.
    /
);
sub undelete_biblio_record_entry {
    my($self, $conn, $auth, $record_id) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('UPDATE_RECORD');

    my $record = $e->retrieve_biblio_record_entry($record_id)
        or return $e->die_event;
    $record->deleted('f');
    $record->active('t');

    # no 2 non-deleted records can have the same tcn_value
    my $existing = $e->search_biblio_record_entry(
        {   deleted => 'f', 
            tcn_value => $record->tcn_value, 
            id => {'!=' => $record_id}
        }, {idlist => 1});
    return OpenILS::Event->new('TCN_EXISTS') if @$existing;

    $e->update_biblio_record_entry($record) or return $e->die_event;
    $e->commit;
    return 1;
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
	my( $self, $client, $authtoken, $xml, $source, $auto_tcn) = @_;
    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('IMPORT_MARC', $e->requestor->ws_ou);

    my $res = OpenILS::Application::Cat::BibCommon->biblio_record_xml_import(
        $e, $xml, $source, $auto_tcn, $self->api_name =~ /override/);

    $e->commit unless $U->event_code($res);
    return $res;
}

__PACKAGE__->register_method(
	method	=> "biblio_record_record_metadata",
	api_name	=> "open-ils.cat.biblio.record.metadata.retrieve",
    authoritative => 1,
	argc		=> 1, #(session_id, biblio_tree ) 
	notes		=> "Walks the tree and commits any changed nodes " .
					"adds any new nodes, and deletes any deleted nodes",
);

sub biblio_record_record_metadata {
	my( $self, $client, $authtoken, $ids ) = @_;

	return [] unless $ids and @$ids;

	my $editor = new_editor(authtoken => $authtoken);
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

	my $session = OpenSRF::AppSession->create("open-ils.cstore");
	my $marc = $session
		->request("open-ils.cstore.direct.biblio.record_entry.retrieve", $id )
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


__PACKAGE__->register_method(
	method	=> "orgs_for_title",
    authoritative => 1,
	api_name	=> "open-ils.cat.actor.org_unit.retrieve_by_title"
);

sub orgs_for_title {
	my( $self, $client, $record_id ) = @_;

	my $vols = $U->simple_scalar_request(
		"open-ils.cstore",
		"open-ils.cstore.direct.asset.call_number.search.atomic",
		{ record => $record_id, deleted => 'f' });

	my $orgs = { map {$_->owning_lib => 1 } @$vols };
	return [ keys %$orgs ];
}


__PACKAGE__->register_method(
	method	=> "retrieve_copies",
    authoritative => 1,
	api_name	=> "open-ils.cat.asset.copy_tree.retrieve");

__PACKAGE__->register_method(
	method	=> "retrieve_copies",
	api_name	=> "open-ils.cat.asset.copy_tree.global.retrieve");

# user_session may be null/undef
sub retrieve_copies {

	my( $self, $client, $user_session, $docid, @org_ids ) = @_;

	if(ref($org_ids[0])) { @org_ids = @{$org_ids[0]}; }

	$docid = "$docid";

	# grabbing copy trees should be available for everyone..
	if(!@org_ids and $user_session) {
		my $user_obj = 
			OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error
			@org_ids = ($user_obj->home_ou);
	}

	if( $self->api_name =~ /global/ ) {
		return _build_volume_list( { record => $docid, deleted => 'f', label => { '<>' => '##URI##' } } );

	} else {

		my @all_vols;
		for my $orgid (@org_ids) {
			my $vols = _build_volume_list( 
					{ record => $docid, owning_lib => $orgid, deleted => 'f', label => { '<>' => '##URI##' } } );
			push( @all_vols, @$vols );
		}
		
		return \@all_vols;
	}

	return undef;
}


sub _build_volume_list {
	my $search_hash = shift;

	$search_hash->{deleted} = 'f';
	my $e = new_editor();

	my $vols = $e->search_asset_call_number($search_hash);

	my @volumes;

	for my $volume (@$vols) {

		my $copies = $e->search_asset_copy(
			{ call_number => $volume->id , deleted => 'f' });

		$copies = [ sort { $a->barcode cmp $b->barcode } @$copies  ];

		for my $c (@$copies) {
			if( $c->status == OILS_COPY_STATUS_CHECKED_OUT ) {
				$c->circulations(
					$e->search_action_circulation(
						[
							{ target_copy => $c->id },
							{
								order_by => { circ => 'xact_start desc' },
								limit => 1
							}
						]
					)
				)
			}
		}

		$volume->copies($copies);
		push( @volumes, $volume );
	}

	#$session->disconnect();
	return \@volumes;

}


__PACKAGE__->register_method(
	method	=> "fleshed_copy_update",
	api_name	=> "open-ils.cat.asset.copy.fleshed.batch.update",);

__PACKAGE__->register_method(
	method	=> "fleshed_copy_update",
	api_name	=> "open-ils.cat.asset.copy.fleshed.batch.update.override",);


sub fleshed_copy_update {
	my( $self, $conn, $auth, $copies, $delete_stats ) = @_;
	return 1 unless ref $copies;
	my( $reqr, $evt ) = $U->checkses($auth);
	return $evt if $evt;
	my $editor = new_editor(requestor => $reqr, xact => 1);
	my $override = $self->api_name =~ /override/;
    my $retarget_holds = [];
	$evt = OpenILS::Application::Cat::AssetCommon->update_fleshed_copies(
        $editor, $override, undef, $copies, $delete_stats, $retarget_holds);

	if( $evt ) { 
		$logger->info("fleshed copy update failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
		$editor->rollback; 
		return $evt; 
	}

	$editor->commit;
	$logger->info("fleshed copy update successfully updated ".scalar(@$copies)." copies");
    reset_hold_list($auth, $retarget_holds);

	return 1;
}

sub reset_hold_list {
    my($auth, $hold_ids) = @_;
    return unless @$hold_ids;
    $logger->info("reseting holds after copy status change: @$hold_ids");
    my $ses = OpenSRF::AppSession->create('open-ils.circ');
    $ses->request('open-ils.circ.hold.reset.batch', $auth, $hold_ids);
}


__PACKAGE__->register_method(
	method => 'merge',
	api_name	=> 'open-ils.cat.biblio.records.merge',
	signature	=> q/
		Merges a group of records
		@param auth The login session key
		@param master The id of the record all other records should be merged into
		@param records Array of records to be merged into the master record
		@return 1 on success, Event on error.
	/
);

sub in_db_merge {
	my( $self, $conn, $auth, $master, $records ) = @_;
	my( $reqr, $evt ) = $U->checkses($auth);
	return $evt if $evt;

	my $editor = new_editor( requestor => $reqr, xact => 1 );

    my $count = 0;
    for my $source ( @$records ) {
        #XXX we actually /will/ want to check perms for master and sources after record ownership exists

        # This stored proc (asset.merge_record_assets(target,source)) has the side effects of
        # moving call_number, title-type (and some volume-type) hold_request and uri-mapping
        # objects from the source record to the target record, so must be called from within
        # a transaction.

        $count += $editor->json_query({
            select => {
                bre => [{
                    alias => 'count',
                    transform => 'asset.merge_record_assets',
                    column => 'id',
                    params => [$source]
                }]
            },
            from   => 'bre',
            where  => { id => $master }
        })->[0]->{count}; # count of objects moved, of all types

    }

	$editor->commit;
    return $count;
}

sub merge {
	my( $self, $conn, $auth, $master, $records ) = @_;
	my( $reqr, $evt ) = $U->checkses($auth);
	return $evt if $evt;
	my $editor = new_editor( requestor => $reqr, xact => 1 );
	my $v = OpenILS::Application::Cat::Merge::merge_records($editor, $master, $records);
	return $v if $v;
	$editor->commit;
    # tell the client the merge is complete, then merge the holds
    $conn->respond_complete(1);
    merge_holds($master, $records);
	return undef;
}

sub merge_holds {
    my($master, $records) = @_;
    return unless $master and @$records;
    return if @$records == 1 and $master == $$records[0];

    my $e = new_editor(xact=>1);
    my $holds = $e->search_action_hold_request(
        {   cancel_time => undef, 
            fulfillment_time => undef,
            hold_type => 'T',
            target => $records
        },
        {idlist=>1}
    );

    for my $hold_id (@$holds) {

        my $hold = $e->retrieve_action_hold_request($hold_id);

        $logger->info("Changing hold ".$hold->id.
            " target from ".$hold->target." to $master in record merge");

        $hold->target($master);
        unless($e->update_action_hold_request($hold)) {
            my $evt = $e->event;
            $logger->error("Error updating hold ". $evt->textcode .":". $evt->desc .":". $evt->stacktrace); 
        }
    }

    $e->commit;
    return undef;
}


__PACKAGE__->register_method(
	method	=> "fleshed_volume_update",
	api_name	=> "open-ils.cat.asset.volume.fleshed.batch.update",);

__PACKAGE__->register_method(
	method	=> "fleshed_volume_update",
	api_name	=> "open-ils.cat.asset.volume.fleshed.batch.update.override",);

sub fleshed_volume_update {
	my( $self, $conn, $auth, $volumes, $delete_stats ) = @_;
	my( $reqr, $evt ) = $U->checkses($auth);
	return $evt if $evt;

	my $override = ($self->api_name =~ /override/);
	my $editor = new_editor( requestor => $reqr, xact => 1 );
    my $retarget_holds = [];

	for my $vol (@$volumes) {
		$logger->info("vol-update: investigating volume ".$vol->id);

		$vol->editor($reqr->id);
		$vol->edit_date('now');

		my $copies = $vol->copies;
		$vol->clear_copies;

		$vol->editor($editor->requestor->id);
		$vol->edit_date('now');

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
			$evt = OpenILS::Application::Cat::AssetCommon->create_volume( $override, $editor, $vol );
			return $evt if $evt;

		} elsif( $vol->ischanged ) {
			$logger->info("vol-update: update volume");
			$evt = update_volume($vol, $editor);
			return $evt if $evt;
		}

		# now update any attached copies
		if( $copies and @$copies and !$vol->isdeleted ) {
			$_->call_number($vol->id) for @$copies;
			$evt = OpenILS::Application::Cat::AssetCommon->update_fleshed_copies(
                $editor, $override, $vol, $copies, $delete_stats, $retarget_holds);
			return $evt if $evt;
		}
	}

	$editor->finish;
    reset_hold_list($auth, $retarget_holds);
	return scalar(@$volumes);
}


sub update_volume {
	my $vol = shift;
	my $editor = shift;
	my $evt;

	return $evt if ( $evt = OpenILS::Application::Cat::AssetCommon->org_cannot_have_vols($editor, $vol->owning_lib) );

	my $vols = $editor->search_asset_call_number( { 
			owning_lib	=> $vol->owning_lib,
			record		=> $vol->record,
			label			=> $vol->label,
			deleted		=> 'f'
		}
	);

	# There exists a different volume in the DB with the same properties
	return OpenILS::Event->new('VOLUME_LABEL_EXISTS', payload => $vol->id)
		if grep { $_->id ne $vol->id } @$vols;

	return $editor->event unless $editor->update_asset_call_number($vol);
	return undef;
}



__PACKAGE__->register_method (
	method => 'delete_bib_record',
	api_name => 'open-ils.cat.biblio.record_entry.delete');

sub delete_bib_record {
    my($self, $conn, $auth, $rec_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('DELETE_RECORD', $e->requestor->ws_ou);
    my $vols = $e->search_asset_call_number({record=>$rec_id, deleted=>'f'});
    return OpenILS::Event->new('RECORD_NOT_EMPTY', payload=>$rec_id) if @$vols;
    my $evt = OpenILS::Application::Cat::BibCommon->delete_rec($e, $rec_id);
    if($evt) { $e->rollback; return $evt; }   
    $e->commit;
    return 1;
}



__PACKAGE__->register_method (
	method => 'batch_volume_transfer',
	api_name => 'open-ils.cat.asset.volume.batch.transfer',
);

__PACKAGE__->register_method (
	method => 'batch_volume_transfer',
	api_name => 'open-ils.cat.asset.volume.batch.transfer.override',
);


sub batch_volume_transfer {
	my( $self, $conn, $auth, $args ) = @_;

	my $evt;
	my $rec		= $$args{docid};
	my $o_lib	= $$args{lib};
	my $vol_ids = $$args{volumes};

	my $override = 1 if $self->api_name =~ /override/;

	$logger->info("merge: transferring volumes to lib=$o_lib and record=$rec");

	my $e = new_editor(authtoken => $auth, xact =>1);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('UPDATE_VOLUME', $o_lib);

	my $dorg = $e->retrieve_actor_org_unit($o_lib)
		or return $e->event;

	my $ou_type = $e->retrieve_actor_org_unit_type($dorg->ou_type)
		or return $e->event;

	return $evt if ( $evt = OpenILS::Application::Cat::AssetCommon->org_cannot_have_vols($e, $o_lib) );

	my $vols = $e->batch_retrieve_asset_call_number($vol_ids);
	my @seen;

   my @rec_ids;

	for my $vol (@$vols) {

        # if we've already looked at this volume, go to the next
        next if !$vol or grep { $vol->id == $_ } @seen;

		# grab all of the volumes in the list that have 
		# the same label so they can be merged
		my @all = grep { $_->label eq $vol->label } @$vols;

		# take note of the fact that we've looked at this set of volumes
		push( @seen, $_->id ) for @all;
        push( @rec_ids, $_->record ) for @all;

		# for each volume, see if there are any copies that have a 
		# remote circ_lib (circ_lib != vol->owning_lib and != $o_lib ).  
		# if so, warn them
		unless( $override ) {
			for my $v (@all) {

				$logger->debug("merge: searching for copies with remote circ_lib for volume ".$v->id);
				my $args = { 
					call_number	=> $v->id, 
					circ_lib		=> { "not in" => [ $o_lib, $v->owning_lib ] },
					deleted		=> 'f'
				};

				my $copies = $e->search_asset_copy($args, {idlist=>1});

				# if the copy's circ_lib matches the destination lib,
				# that's ok too
				return OpenILS::Event->new('COPY_REMOTE_CIRC_LIB') if @$copies;
			}
		}

		# see if there is a volume at the destination lib that 
		# already has the requested label
		my $existing_vol = $e->search_asset_call_number(
			{
				label			=> $vol->label, 
				record		=>$rec, 
				owning_lib	=>$o_lib,
				deleted		=> 'f'
			}
		)->[0];

		if( $existing_vol ) {

			if( grep { $_->id == $existing_vol->id } @all ) {
				# this volume is already accounted for in our list of volumes to merge
				$existing_vol = undef;

			} else {
				# this volume exists on the destination record/owning_lib and must
				# be used as the destination for merging
				$logger->debug("merge: volume already exists at destination record: ".
					$existing_vol->id.' : '.$existing_vol->label) if $existing_vol;
			}
		} 

		if( @all > 1 || $existing_vol ) {
			$logger->info("merge: found collisions in volume transfer");
			my @args = ($e, \@all);
			@args = ($e, \@all, $existing_vol) if $existing_vol;
			($vol, $evt) = OpenILS::Application::Cat::Merge::merge_volumes(@args);
			return $evt if $evt;
		} 
		
		if( !$existing_vol ) {

			$vol->owning_lib($o_lib);
			$vol->record($rec);
			$vol->editor($e->requestor->id);
			$vol->edit_date('now');
	
			$logger->info("merge: updating volume ".$vol->id);
			$e->update_asset_call_number($vol) or return $e->event;

		} else {
			$logger->info("merge: bypassing volume update because existing volume used as target");
		}

		# regardless of what volume was used as the destination, 
		# update any copies that have moved over to the new lib
		my $copies = $e->search_asset_copy({call_number=>$vol->id, deleted => 'f'});

		# update circ lib on the copies - make this a method flag?
		for my $copy (@$copies) {
			next if $copy->circ_lib == $o_lib;
			$logger->info("merge: transfer moving circ lib on copy ".$copy->id);
			$copy->circ_lib($o_lib);
			$copy->editor($e->requestor->id);
			$copy->edit_date('now');
			$e->update_asset_copy($copy) or return $e->event;
		}

		# Now see if any empty records need to be deleted after all of this

        for(@rec_ids) {
            $logger->debug("merge: seeing if we should delete record $_...");
            $evt = OpenILS::Application::Cat::BibCommon->delete_rec($e, $_) 
                if OpenILS::Application::Cat::BibCommon->title_is_empty($e, $_);
            return $evt if $evt;
        }
	}

	$logger->info("merge: transfer succeeded");
	$e->commit;
	return 1;
}




__PACKAGE__->register_method(
	api_name => 'open-ils.cat.call_number.find_or_create',
	method => 'find_or_create_volume',
);

sub find_or_create_volume {
	my( $self, $conn, $auth, $label, $record_id, $org_id ) = @_;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
    my ($vol, $evt, $exists) = 
        OpenILS::Application::Cat::AssetCommon->find_or_create_volume($e, $label, $record_id, $org_id);
    return $evt if $evt;
    $e->rollback if $exists;
    $e->commit if $vol;
    return $vol->id;
}



1;
