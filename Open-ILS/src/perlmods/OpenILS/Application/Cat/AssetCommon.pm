package OpenILS::Application::Cat::AssetCommon;
use strict; use warnings;
use OpenILS::Application::Cat::BibCommon;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger qw($logger);
use OpenILS::Application::Cat::Merge;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw/:const/;
use OpenSRF::AppSession;
use OpenILS::Event;
my $U = 'OpenILS::Application::AppUtils';


# ---------------------------------------------------------------------------
# Shared copy mangling code.  Do not publish methods from here.
# ---------------------------------------------------------------------------

sub org_cannot_have_vols {
    my($class, $e, $org_id) = @_;
	my $org = $e->retrieve_actor_org_unit([
        $org_id,
        {   flesh => 1,
            flesh_fields => {aou => ['ou_type']}
        }]) or return $e->event;

	return OpenILS::Event->new('ORG_CANNOT_HAVE_VOLS')
		unless $U->is_true($org->ou_type->can_have_vols);

	return 0;
}

sub fix_copy_price {
    my $class = shift;
	my $copy = shift;

    if(defined $copy->price) {
	    my $p = $copy->price || 0;
	    $p =~ s/\$//og;
	    $copy->price($p);
    }

	my $d = $copy->deposit_amount || 0;
	$d =~ s/\$//og;
	$copy->deposit_amount($d);
}

sub create_copy {
	my($class, $editor, $vol, $copy) = @_;

	my $existing = $editor->search_asset_copy(
		{ barcode => $copy->barcode, deleted => 'f' } );
	
	return OpenILS::Event->new('ITEM_BARCODE_EXISTS') if @$existing;

   # see if the volume this copy references is marked as deleted
    return OpenILS::Event->new('VOLUME_DELETED', vol => $vol->id) 
        if $U->is_true($vol->deleted);

	my $evt;
	my $org = (ref $copy->circ_lib) ? $copy->circ_lib->id : $copy->circ_lib;
	return $evt if ($evt = OpenILS::Application::Cat::AssetCommon->org_cannot_have_vols($editor, $org));

	$copy->clear_id;
	$copy->editor($editor->requestor->id);
	$copy->creator($editor->requestor->id);
	$copy->create_date('now');
    $copy->call_number($vol->id);
	$class->fix_copy_price($copy);

	$editor->create_asset_copy($copy) or return $editor->die_event;
	return undef;
}


# if 'delete_stats' is true, the copy->stat_cat_entries data is 
# treated as the authoritative list for the copy. existing entries
# that are not in said list will be deleted from the DB
sub update_copy_stat_entries {
	my($class, $editor, $copy, $delete_stats) = @_;

	return undef if $copy->isdeleted;
	return undef unless $copy->ischanged or $copy->isnew;

	my $evt;
	my $entries = $copy->stat_cat_entries;

	if( $delete_stats ) {
		$entries = ($entries and @$entries) ? $entries : [];
	} else {
		return undef unless ($entries and @$entries);
	}

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
		next unless $entry;

		# if this link already exists in the DB, don't attempt to re-create it
		next if( grep{$_->stat_cat_entry == $entry->id} @$maps );
	
		my $new_map = Fieldmapper::asset::stat_cat_entry_copy_map->new();

		my $sc = ref($entry->stat_cat) ? $entry->stat_cat->id : $entry->stat_cat;
		
		$new_map->stat_cat( $sc );
		$new_map->stat_cat_entry( $entry->id );
		$new_map->owning_copy( $copy->id );

		$editor->create_asset_stat_cat_entry_copy_map($new_map)
			or return $editor->event;

		$logger->info("copy update created new stat cat entry map ".$editor->data);
	}

	return undef;
}


sub update_copy {
	my($class, $editor, $override, $vol, $copy) = @_;

	my $evt;
	my $org = (ref $copy->circ_lib) ? $copy->circ_lib->id : $copy->circ_lib;
	return $evt if ( $evt = OpenILS::Application::Cat::AssetCommon->org_cannot_have_vols($editor, $org) );

	$logger->info("vol-update: updating copy ".$copy->id);
	my $orig_copy = $editor->retrieve_asset_copy($copy->id);
	my $orig_vol  = $editor->retrieve_asset_call_number($copy->call_number);

	$copy->editor($editor->requestor->id);
	$copy->edit_date('now');

	$copy->age_protect( $copy->age_protect->id )
		if ref $copy->age_protect;

	$class->fix_copy_price($copy);

	return $editor->event unless $editor->update_asset_copy($copy);
	return $class->remove_empty_objects($editor, $override, $orig_vol);
}


# this does the actual work
sub update_fleshed_copies {
	my($class, $editor, $override, $vol, $copies, $delete_stats) = @_;

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

		return $editor->event unless 
			$editor->allowed('UPDATE_COPY', $class->copy_perm_org($vol, $copy));

		$copy->editor($editor->requestor->id);
		$copy->edit_date('now');

		$copy->status( $copy->status->id ) if ref($copy->status);
		$copy->location( $copy->location->id ) if ref($copy->location);
		$copy->circ_lib( $copy->circ_lib->id ) if ref($copy->circ_lib);
		
		my $sc_entries = $copy->stat_cat_entries;
		$copy->clear_stat_cat_entries;

		if( $copy->isdeleted ) {
			$evt = $class->delete_copy($editor, $override, $vol, $copy);
			return $evt if $evt;

		} elsif( $copy->isnew ) {
			$evt = $class->create_copy( $editor, $vol, $copy );
			return $evt if $evt;

		} elsif( $copy->ischanged ) {

			$evt = $class->update_copy( $editor, $override, $vol, $copy );
			return $evt if $evt;
		}

		$copy->stat_cat_entries( $sc_entries );
		$evt = $class->update_copy_stat_entries($editor, $copy, $delete_stats);
		return $evt if $evt;
	}

	$logger->debug("vol-update: done updating copy batch");

	return undef;
}


sub delete_copy {
	my($class, $editor, $override, $vol, $copy ) = @_;

   return $editor->event unless 
      $editor->allowed('DELETE_COPY', $class->copy_perm_org($vol, $copy));

	my $stat = $U->copy_status($copy->status)->id;

	unless($override) {
		return OpenILS::Event->new('COPY_DELETE_WARNING', payload => $copy->id )
			if $stat == OILS_COPY_STATUS_CHECKED_OUT or
				$stat == OILS_COPY_STATUS_IN_TRANSIT or
				$stat == OILS_COPY_STATUS_ON_HOLDS_SHELF or
				$stat == OILS_COPY_STATUS_ILL;
	}

	$logger->info("vol-update: deleting copy ".$copy->id);
	$copy->deleted('t');

	$copy->editor($editor->requestor->id);
	$copy->edit_date('now');
	$editor->update_asset_copy($copy) or return $editor->event;

	# Delete any open transits for this copy
	my $transits = $editor->search_action_transit_copy(
		{ target_copy=>$copy->id, dest_recv_time => undef } );

	for my $t (@$transits) {
		$editor->delete_action_transit_copy($t)
			or return $editor->event;
	}

	return $class->remove_empty_objects($editor, $override, $vol);
}



sub create_volume {
	my($class, $override, $editor, $vol) = @_;
	my $evt;

	return $evt if ( $evt = $class->org_cannot_have_vols($editor, $vol->owning_lib) );

   # see if the record this volume references is marked as deleted
   my $rec = $editor->retrieve_biblio_record_entry($vol->record)
      or return $editor->die_event;
   return OpenILS::Event->new('BIB_RECORD_DELETED', rec => $rec->id) 
      if $U->is_true($rec->deleted);

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
      # we've found an exising volume
		if($override) { 
			$label = $vol->label;
		} else {
			return OpenILS::Event->new(
				'VOLUME_LABEL_EXISTS', payload => $vol->id);
		}
	}

	# create a temp label so we can create the new volume, 
    # then de-dup it with the existing volume
	$vol->label( "__SYSTEM_TMP_$$".time) if $label;

	$vol->creator($editor->requestor->id);
	$vol->create_date('now');
	$vol->editor($editor->requestor->id);
	$vol->edit_date('now');
	$vol->clear_id;

	$editor->create_asset_call_number($vol) or return $editor->die_event;

	if($label) {
		# now restore the label and merge into the existing record
		$vol->label($label);
		(undef, $evt) = 
			OpenILS::Application::Cat::Merge::merge_volumes($editor, [$vol], $$vols[0]);
		return $evt if $evt;
	}

	return undef;
}

# returns the volume if it exists
sub volume_exists {
    my($class, $e, $rec_id, $label, $owning_lib) = @_;
    return $e->search_asset_call_number(
        {label => $label, record => $rec_id, owning_lib => $owning_lib, deleted => 'f'})->[0];
}

sub find_or_create_volume {
	my($class, $e, $label, $record_id, $org_id) = @_;

    my $vol;

    if($record_id == OILS_PRECAT_RECORD) {
        $vol = $e->retrieve_asset_call_number(OILS_PRECAT_CALL_NUMBER)
            or return (undef, $e->die_event);

    } else {
        $vol = $class->volume_exists($e, $record_id, $label, $org_id);
    }

	# If the volume exists, return the ID
    return ($vol, undef, 1) if $vol;

	# -----------------------------------------------------------------
	# Otherwise, create a new volume with the given attributes
	# -----------------------------------------------------------------
	return (undef, $e->die_event) unless $e->allowed('UPDATE_VOLUME', $org_id);

	$vol = Fieldmapper::asset::call_number->new;
	$vol->owning_lib($org_id);
	$vol->label($label);
	$vol->record($record_id);

    my $evt = OpenILS::Application::Cat::AssetCommon->create_volume(0, $e, $vol);
    return (undef, $evt) if $evt;

	return ($vol);
}


sub create_copy_note {
    my($class, $e, $copy, $title, $value, $pub) = @_;
    my $note = Fieldmapper::asset::copy_note->new;
    $note->owning_copy($copy->id);
    $note->creator($e->requestor->id);
    $note->pub('t');
    $note->value($value);
    $note->title($title);
    $e->create_asset_copy_note($note) or return $e->die_event;
    return undef;
}


sub remove_empty_objects {
	my($class, $editor, $override, $vol) = @_; 

    my $koe = $U->ou_ancestor_setting_value(
        $editor->requestor->ws_ou, 'cat.bib.keep_on_empty', $editor);
    my $aoe =  $U->ou_ancestor_setting_value(
        $editor->requestor->ws_ou, 'cat.bib.alert_on_empty', $editor);

	if( OpenILS::Application::Cat::BibCommon->title_is_empty($editor, $vol->record, $vol->id) ) {

        # delete this volume if it's not already marked as deleted
        unless( $U->is_true($vol->deleted) || $vol->isdeleted ) {
            $vol->deleted('t');
            $vol->editor($editor->requestor->id);
            $vol->edit_date('now');
            $editor->update_asset_call_number($vol) or return $editor->event;
        }

        unless($koe) {
            # delete the bib record if the keep-on-empty setting is not set
            my $evt = OpenILS::Application::Cat::BibCommon->delete_rec($editor, $vol->record);
            return $evt if $evt;
        }

        # return the empty alert if the alert-on-empty setting is set
        return OpenILS::Event->new('TITLE_LAST_COPY', payload => $vol->record ) if $aoe;
	}

	return undef;
}


sub copy_perm_org {
	my($class, $vol, $copy) = @_;
	my $org = $vol->owning_lib;
	if( $vol->id == OILS_PRECAT_CALL_NUMBER ) {
		$org = ref($copy->circ_lib) ? $copy->circ_lib->id : $copy->circ_lib;
	}
	$logger->debug("using copy perm org $org");
	return $org;
}
