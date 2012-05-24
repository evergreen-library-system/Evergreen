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
use OpenILS::Utils::Penalty;
use OpenILS::Application::Circ::CircCommon;
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
	return $evt if ($evt = $class->org_cannot_have_vols($editor, $org));

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

# if 'delete_maps' is true, the copy->parts data is  treated as the
# authoritative list for the copy. existing part maps not targeting
# these parts will be deleted from the DB
sub update_copy_parts {
	my($class, $editor, $copy, $delete_maps) = @_;

	return undef if $copy->isdeleted;
	return undef unless $copy->ischanged or $copy->isnew;

	my $evt;
	my $incoming_parts = $copy->parts;

	if( $delete_maps ) {
		$incoming_parts = ($incoming_parts and @$incoming_parts) ? $incoming_parts : [];
	} else {
		return undef unless ($incoming_parts and @$incoming_parts);
	}

	my $maps = $editor->search_asset_copy_part_map({target_copy=>$copy->id});

	if(!$copy->isnew) {
		# if there is no part map on the copy who's id matches the
		# current map's id, remove the map from the database
		for my $map (@$maps) {
			if(! grep { $_->id == $map->part } @$incoming_parts ) {

				$logger->info("copy update found stale ".
					"monographic part map ".$map->id. " on copy ".$copy->id);

				$editor->delete_asset_copy_part_map($map)
					or return $editor->event;
			}
		}
	}

	# go through the part map update/create process
	for my $incoming_part (@$incoming_parts) { 
		next unless $incoming_part;

		# if this link already exists in the DB, don't attempt to re-create it
		next if( grep{$_->part == $incoming_part->id} @$maps );
	
		my $new_map = Fieldmapper::asset::copy_part_map->new();

		$new_map->part( $incoming_part->id );
		$new_map->target_copy( $copy->id );

		$editor->create_asset_copy_part_map($new_map)
			or return $editor->event;

		$logger->info("copy update created new monographic part copy map ".$editor->data);
	}

	return undef;
}



sub update_copy {
	my($class, $editor, $override, $vol, $copy, $retarget_holds, $force_delete_empty_bib) = @_;

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

	my $evt;
	my $org = (ref $copy->circ_lib) ? $copy->circ_lib->id : $copy->circ_lib;
	return $evt if ( $evt = $class->org_cannot_have_vols($editor, $org) );

	$logger->info("vol-update: updating copy ".$copy->id);
	my $orig_copy = $editor->retrieve_asset_copy($copy->id);

    # Call-number may have changed, find the original
    my $orig_vol_id = $editor->json_query({select => {acp => ['call_number']}, from => 'acp', where => {id => $copy->id}});
    my $orig_vol  = $editor->retrieve_asset_call_number($orig_vol_id->[0]->{call_number});

	$copy->editor($editor->requestor->id);
	$copy->edit_date('now');

	$copy->age_protect( $copy->age_protect->id )
		if ref $copy->age_protect;

	$class->fix_copy_price($copy);
    $class->check_hold_retarget($editor, $copy, $orig_copy, $retarget_holds);

	return $editor->event unless $editor->update_asset_copy($copy);
	return $class->remove_empty_objects($editor, $override, $orig_vol, $force_delete_empty_bib);
}

sub check_hold_retarget {
    my($class, $editor, $copy, $orig_copy, $retarget_holds) = @_;
    return unless $retarget_holds;

    if( !($copy->isdeleted or $U->is_true($copy->deleted)) ) {
        # see if a status change warrants a retarget

        $orig_copy = $editor->retrieve_asset_copy($copy->id) unless $orig_copy;

        if($orig_copy->status == $copy->status) {
            # no status change, no retarget
            return;
        }

        my $stat = $editor->retrieve_config_copy_status($copy->status);

        # new status is holdable, no retarget. Later add logic to find potential 
        # holds and retarget those to pick up the newly available copy
        return if $U->is_true($stat->holdable); 
    }

    my $hold_ids = $editor->search_action_hold_request(
        {   current_copy        => $copy->id, 
            cancel_time         => undef, 
            fulfillment_time    => undef 
        }, {idlist => 1}
    );

    push(@$retarget_holds, @$hold_ids);
}


# this does the actual work
sub update_fleshed_copies {
	my($class, $editor, $override, $vol, $copies, $delete_stats, $retarget_holds, $force_delete_empty_bib) = @_;

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

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

        my $parts = $copy->parts;
		$copy->clear_parts;

		if( $copy->isdeleted ) {
			$evt = $class->delete_copy($editor, $override, $vol, $copy, $retarget_holds, $force_delete_empty_bib);
			return $evt if $evt;

		} elsif( $copy->isnew ) {
			$evt = $class->create_copy( $editor, $vol, $copy );
			return $evt if $evt;

		} elsif( $copy->ischanged ) {

			$evt = $class->update_copy( $editor, $override, $vol, $copy, $retarget_holds, $force_delete_empty_bib);
			return $evt if $evt;
		}

		$copy->stat_cat_entries( $sc_entries );
		$evt = $class->update_copy_stat_entries($editor, $copy, $delete_stats);
		$copy->parts( $parts );
		# probably okay to use $delete_stats here for simplicity
		$evt = $class->update_copy_parts($editor, $copy, $delete_stats);
		return $evt if $evt;
	}

	$logger->debug("vol-update: done updating copy batch");

	return undef;
}


sub delete_copy {
	my($class, $editor, $override, $vol, $copy, $retarget_holds, $force_delete_empty_bib, $skip_empty_cleanup) = @_;

	return $editor->event unless
		$editor->allowed('DELETE_COPY', $class->copy_perm_org($vol, $copy));

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

	my $stat = $U->copy_status($copy->status);
	if ($U->is_true($stat->restrict_copy_delete)) {
		if ($override->{all} || grep { $_ eq 'COPY_DELETE_WARNING' } @{$override->{events}}) {
			return $editor->event unless $editor->allowed('COPY_DELETE_WARNING.override', $class->copy_perm_org($vol, $copy))
		} else {
			return OpenILS::Event->new('COPY_DELETE_WARNING', payload => $copy->id )
		}
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

    my $evt = $class->cancel_copy_holds($editor, $copy);
    return $evt if $evt;

    $class->check_hold_retarget($editor, $copy, undef, $retarget_holds);

    return undef if $skip_empty_cleanup;

	return $class->remove_empty_objects($editor, $override, $vol, $force_delete_empty_bib);
}


# deletes all holds that specifically target the deleted copy
sub cancel_copy_holds {
    my($class, $editor, $copy) = @_;

    my $holds = $editor->search_action_hold_request({   
        target              => $copy->id, 
        hold_type           => [qw/C R F/],
        cancel_time         => undef, 
        fulfillment_time    => undef 
    });

    return $class->cancel_hold_list($editor, $holds);
}

# deletes all holds that specifically target the deleted volume
sub cancel_volume_holds {
    my($class, $editor, $volume) = @_;

    my $holds = $editor->search_action_hold_request({   
        target              => $volume->id, 
        hold_type           => 'V',
        cancel_time         => undef, 
        fulfillment_time    => undef 
    });

    return $class->cancel_hold_list($editor, $holds);
}

sub cancel_hold_list {
    my($class, $editor, $holds) = @_;

    for my $hold (@$holds) {

        $hold->cancel_time('now');
        $hold->cancel_cause(1); # un-targeted expiration.  Do we need an alternate "target deleted" cause?
        $editor->update_action_hold_request($hold) or return $editor->die_event;

        # delete the copy maps.  
        my $maps = $editor->search_action_hold_copy_map({hold => $hold->id});
        for(@$maps) {
            $editor->delete_action_hold_copy_map($_) 
                or return $editor->die_event;
        }

        # tell A/T the hold was cancelled.  Don't wait for a response..
        my $at_ses = OpenSRF::AppSession->create('open-ils.trigger');
        $at_ses->request(
            'open-ils.trigger.event.autocreate',
            'hold_request.cancel.expire_no_target', 
            $hold, $hold->pickup_lib);
    }

    return undef;
}



sub create_volume {
	my($class, $override, $editor, $vol) = @_;
	my $evt;

	return $evt if ( $evt = $class->org_cannot_have_vols($editor, $vol->owning_lib) );

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

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
			prefix			=> $vol->prefix,
			suffix			=> $vol->suffix,
			deleted		=> 'f'
		}
	);

	my $label = undef;
	if(@$vols) {
      # we've found an exising volume
		if($override->{all} || grep { $_ eq 'VOLUME_LABEL_EXISTS' } @{$override->{events}}) {
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
    my($class, $e, $rec_id, $label, $owning_lib, $prefix, $suffix) = @_;
    return $e->search_asset_call_number(
        {label => $label, record => $rec_id, owning_lib => $owning_lib, deleted => 'f', prefix => $prefix, suffix => $suffix})->[0];
}

sub find_or_create_volume {
	my($class, $e, $label, $record_id, $org_id, $prefix, $suffix, $label_class) = @_;

    $prefix ||= '-1';
    $suffix ||= '-1';

    my $vol;

    if($record_id == OILS_PRECAT_RECORD) {
        $vol = $e->retrieve_asset_call_number(OILS_PRECAT_CALL_NUMBER)
            or return (undef, $e->die_event);

    } else {
        $vol = $class->volume_exists($e, $record_id, $label, $org_id, $prefix, $suffix);
    }

	# If the volume exists, return the ID
    return ($vol, undef, 1) if $vol;

	# -----------------------------------------------------------------
	# Otherwise, create a new volume with the given attributes
	# -----------------------------------------------------------------
	return (undef, $e->die_event) unless $e->allowed('UPDATE_VOLUME', $org_id);

	$vol = Fieldmapper::asset::call_number->new;
	$vol->owning_lib($org_id);
	$vol->label_class($label_class) if ($label_class);
	$vol->label($label);
	$vol->prefix($prefix);
	$vol->suffix($suffix);
	$vol->record($record_id);

    my $evt = $class->create_volume(0, $e, $vol);
    return (undef, $evt) if $evt;

	return ($vol);
}


sub create_copy_note {
    my($class, $e, $copy, $title, $value, $pub) = @_;
    my $note = Fieldmapper::asset::copy_note->new;
    $note->owning_copy($copy->id);
    $note->creator($e->requestor->id);
    $note->pub($pub ? 't' : 'f');
    $note->value($value);
    $note->title($title);
    $e->create_asset_copy_note($note) or return $e->die_event;
    return undef;
}


sub remove_empty_objects {
	my($class, $editor, $override, $vol, $force_delete_empty_bib) = @_; 

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

    my $koe = $U->ou_ancestor_setting_value(
        $editor->requestor->ws_ou, 'cat.bib.keep_on_empty', $editor);
    my $aoe =  $U->ou_ancestor_setting_value(
        $editor->requestor->ws_ou, 'cat.bib.alert_on_empty', $editor);

	if( OpenILS::Application::Cat::BibCommon->title_is_empty($editor, $vol->record, $vol->id) ) {

        # delete this volume if it's not already marked as deleted
        unless( $U->is_true($vol->deleted) || $vol->isdeleted ) {
            my $evt = $class->delete_volume($editor, $vol, $override, 0, 1);
            return $evt if $evt;
        }

        return OpenILS::Event->new('TITLE_LAST_COPY', payload => $vol->record ) 
            if $aoe and not ($override->{all} || grep { $_ eq 'TITLE_LAST_COPY' } @{$override->{events}}) and not $force_delete_empty_bib;

        unless($koe and not $force_delete_empty_bib) {
            # delete the bib record if the keep-on-empty setting is not set (and we're not otherwise forcing things, say through acq settings)
            my $evt = OpenILS::Application::Cat::BibCommon->delete_rec($editor, $vol->record);
            return $evt if $evt;
        }

	} else {

        # this may be the last copy attached to the volume.  

        if($U->ou_ancestor_setting_value(
                $editor->requestor->ws_ou, 'cat.volume.delete_on_empty', $editor)) {

            # if this volume is "empty" and not mid-delete, delete it.
            unless($U->is_true($vol->deleted) || $vol->isdeleted) {

                my $copies = $editor->search_asset_copy(
                    [{call_number => $vol->id, deleted => 'f'}, {limit => 1}], {idlist => 1});

                if(!@$copies) {
                    my $evt = $class->delete_volume($editor, $vol, $override, 0, 1);
                    return $evt if $evt;
                }
            }
        }
    }

	return undef;
}

# Deletes a volume.  Returns undef on success, event on error
# force : deletes all attached copies
# skip_copy_check : assumes caller has verified no copies need deleting first
sub delete_volume {
    my($class, $editor, $vol, $override, $delete_copies, $skip_copy_checks) = @_;
    my $evt;

    unless($skip_copy_checks) {
        my $cs = $editor->search_asset_copy(
            [{call_number => $vol->id, deleted => 'f'}, {limit => 1}], {idlist => 1});

        return OpenILS::Event->new('VOLUME_NOT_EMPTY', payload => $vol->id) 
            if @$cs and !$delete_copies;

        my $copies = $editor->search_asset_copy({call_number => $vol->id, deleted => 'f'});

        for my $copy (@$copies) {
            $evt = $class->delete_copy($editor, $override, $vol, $copy, 0, 0, 1);
            return $evt if $evt;
        }
    }

    $vol->deleted('t');
    $vol->edit_date('now');
    $vol->editor($editor->requestor->id);
    $editor->update_asset_call_number($vol) or return $editor->die_event;

    $evt = $class->cancel_volume_holds($editor, $vol);
    return $evt if $evt;

    # handle the case where this is the last volume on the record
	return $class->remove_empty_objects($editor, $override, $vol);
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


sub set_item_lost {
    my($class, $e, $copy_id) = @_;

    my $copy = $e->retrieve_asset_copy([
        $copy_id, 
        {flesh => 1, flesh_fields => {'acp' => ['call_number']}}])
            or return $e->die_event;

    my $owning_lib = 
        ($copy->call_number->id == OILS_PRECAT_CALL_NUMBER) ? 
            $copy->circ_lib : $copy->call_number->owning_lib;

    my $circ = $e->search_action_circulation(
        {checkin_time => undef, target_copy => $copy->id} )->[0]
            or return $e->die_event;

    $e->allowed('SET_CIRC_LOST', $circ->circ_lib) or return $e->die_event;

    return $e->die_event(OpenILS::Event->new('COPY_MARKED_LOST'))
	    if $copy->status == OILS_COPY_STATUS_LOST;

    # ---------------------------------------------------------------------
    # fetch the related org settings
    my $proc_fee = $U->ou_ancestor_setting_value(
        $owning_lib, OILS_SETTING_LOST_PROCESSING_FEE, $e) || 0;
    my $void_overdue = $U->ou_ancestor_setting_value(
        $owning_lib, OILS_SETTING_VOID_OVERDUE_ON_LOST, $e) || 0;

    # ---------------------------------------------------------------------
    # move the copy into LOST status
    $copy->status(OILS_COPY_STATUS_LOST);
    $copy->editor($e->requestor->id);
    $copy->edit_date('now');
    $e->update_asset_copy($copy) or return $e->die_event;

    my $price = $U->get_copy_price($e, $copy, $copy->call_number);

    if( $price > 0 ) {
        my $evt = OpenILS::Application::Circ::CircCommon->create_bill(
            $e, $price, 3, 'Lost Materials', $circ->id);
        return $evt if $evt;
    }

    # ---------------------------------------------------------------------
    # if there is a processing fee, charge that too
    if( $proc_fee > 0 ) {
        my $evt = OpenILS::Application::Circ::CircCommon->create_bill(
            $e, $proc_fee, 4, 'Lost Materials Processing Fee', $circ->id);
        return $evt if $evt;
    }

    # ---------------------------------------------------------------------
    # mark the circ as lost and stop the fines
    $circ->stop_fines(OILS_STOP_FINES_LOST);
    $circ->stop_fines_time('now') unless $circ->stop_fines_time;
    $e->update_action_circulation($circ) or return $e->die_event;

    # ---------------------------------------------------------------------
    # void all overdue fines on this circ if configured
    if( $void_overdue ) {
        my $evt = OpenILS::Application::Circ::CircCommon->void_overdues($e, $circ);
        return $evt if $evt;
    }

    my $evt = OpenILS::Application::Circ::CircCommon->reopen_xact($e, $circ->id);
    return $evt if $evt;

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    $ses->request('open-ils.trigger.event.autocreate', 'lost', $circ, $circ->circ_lib);

    my $evt2 = OpenILS::Utils::Penalty->calculate_penalties($e, $circ->usr, $U->xact_org($circ->id,$e));
    return $evt2 if $evt2;

    return undef;
}
