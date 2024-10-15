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

    return $editor->event unless
        $editor->allowed('CREATE_COPY', $class->copy_perm_org($vol, $copy));

    my $existing = $editor->search_asset_copy(
        { barcode => $copy->barcode, deleted => 'f' } );
    
    return OpenILS::Event->new('ITEM_BARCODE_EXISTS') if @$existing;

    my $copy_loc = $editor->search_asset_copy_location(
        { id => $copy->location, deleted => 'f' } );
        
    return OpenILS::Event->new('COPY_LOCATION_NOT_FOUND') unless @$copy_loc;
    
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

    my $cp = $editor->create_asset_copy($copy) or return $editor->die_event;
    $copy->id($cp->id);
    return undef;
}


# 'delete_stats' is somewhat of a misnomer.  With no flags set, this method
# still deletes any existing maps not represented in $copy->stat_cat_entries,
# but aborts when $copy->stat_cat_entries is empty or undefined.  If
# 'delete_stats' is true, this method will delete all the maps when
# $copy->stat_cat_entries is empty or undefined.
#
# The 'add_or_update_only' flag is more straightforward.  It adds missing
# maps, updates present maps with any new values, and leaves the rest
# alone.
sub update_copy_stat_entries {
    my($class, $editor, $copy, $delete_stats, $add_or_update_only) = @_;

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
            if (!$add_or_update_only) {
                if(! grep { $_->id == $map->stat_cat_entry } @$entries ) {

                    $logger->info("copy update found stale ".
                        "stat cat entry map ".$map->id. " on copy ".$copy->id);

                    $editor->delete_asset_stat_cat_entry_copy_map($map)
                        or return $editor->event;
                }
            } else {
                if( grep { $_->stat_cat == $map->stat_cat and $_->id != $map->stat_cat_entry } @$entries ) {

                    $logger->info("copy update found ".
                        "stat cat entry map ".$map->id. " needing update on copy ".$copy->id);

                    $editor->delete_asset_stat_cat_entry_copy_map($map)
                        or return $editor->event;
                }
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
    my($class, $editor, $copy, $delete_maps, $create_parts) = @_;

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

        if ($incoming_part->isnew) {
            next unless $create_parts;
            my $new_part = Fieldmapper::biblio::monograph_part->new();
            $new_part->record( $incoming_part->record );
            $new_part->label( $incoming_part->label );
            $incoming_part = $editor->create_biblio_monograph_part($new_part)
                or return $editor->event;
        }
    
        my $new_map = Fieldmapper::asset::copy_part_map->new();

        $new_map->part( $incoming_part->id );
        $new_map->target_copy( $copy->id );

        $editor->create_asset_copy_part_map($new_map)
            or return $editor->event;

        $logger->info("copy update created new monographic part copy map ".$editor->data);
    }

    return undef;
}



sub update_copy_notes {
    my($class, $editor, $copy) = @_;

    return undef if $copy->isdeleted;

    my $evt;
    my $incoming_notes = $copy->notes;

    for my $incoming_note (@$incoming_notes) { 
        next unless $incoming_note;

        if ($incoming_note->isnew) {
            next if ($incoming_note->isdeleted); # if it was added and deleted in the same session

            my $new_note = Fieldmapper::asset::copy_note->new();
            $new_note->owning_copy( $copy->id );
            $new_note->pub( $incoming_note->pub );
            $new_note->title( $incoming_note->title );
            $new_note->value( $incoming_note->value );
            $new_note->creator( $incoming_note->creator || $editor->requestor->id );
            $incoming_note = $editor->create_asset_copy_note($new_note)
                or return $editor->event;

        } elsif ($incoming_note->ischanged) {
            $incoming_note = $editor->update_asset_copy_note($incoming_note)
        } elsif ($incoming_note->isdeleted) {
            $incoming_note = $editor->delete_asset_copy_note($incoming_note)
        }
    
    }

    return undef;
}

sub update_copy_alerts {
    my($class, $editor, $copy) = @_;

    return undef if $copy->isdeleted;

    my $evt;
    my $incoming_copy_alerts = $copy->copy_alerts;

    for my $incoming_copy_alert (@$incoming_copy_alerts) { 
        next unless $incoming_copy_alert;

        if ($incoming_copy_alert->isnew) {
            next if ($incoming_copy_alert->isdeleted); # if it was added and deleted in the same session

            my $new_copy_alert = Fieldmapper::asset::copy_alert->new();
            $new_copy_alert->copy( $copy->id );
            $new_copy_alert->temp( $incoming_copy_alert->temp );
            $new_copy_alert->ack_time( $incoming_copy_alert->ack_time );
            $new_copy_alert->note( $incoming_copy_alert->note );
            $new_copy_alert->alert_type( $incoming_copy_alert->alert_type );
            $new_copy_alert->create_staff( $incoming_copy_alert->create_staff || $editor->requestor->id );
            $incoming_copy_alert = $editor->create_asset_copy_alert($new_copy_alert)
                or return $editor->event;
        } elsif ($incoming_copy_alert->ischanged) {
            $incoming_copy_alert = $editor->update_asset_copy_alert($incoming_copy_alert)
        } elsif ($incoming_copy_alert->isdeleted) {
            $incoming_copy_alert = $editor->delete_asset_copy_alert($incoming_copy_alert->id)
        }
    
    }

    return undef;
}

sub update_copy_tags {
    my($class, $editor, $copy) = @_;

    return undef if $copy->isdeleted;

    my $evt;
    my $incoming_maps = $copy->tags;

    for my $incoming_map (@$incoming_maps) {
        next unless $incoming_map;

        if ($incoming_map->isnew) {
            next if ($incoming_map->isdeleted); # if it was added and deleted in the same session

            my $tag_id;
            if ($incoming_map->tag->isnew) {
                my $new_tag = Fieldmapper::asset::copy_tag->new();
                $new_tag->owner( $incoming_map->tag->owner );
                $new_tag->label( $incoming_map->tag->label );
                $new_tag->tag_type( $incoming_map->tag->tag_type );
                $new_tag->pub( $incoming_map->tag->pub );
                my $tag = $editor->create_asset_copy_tag($new_tag)
                    or return $editor->event;
                $tag_id = $tag->id;
            } else {
                $tag_id = $incoming_map->tag->id;
            }
            my $new_map = Fieldmapper::asset::copy_tag_copy_map->new();
            $new_map->copy( $copy->id );
            $new_map->tag( $tag_id );
            $incoming_map = $editor->create_asset_copy_tag_copy_map($new_map)
                or return $editor->event;

        } elsif ($incoming_map->ischanged) {
            $incoming_map = $editor->update_asset_copy_tag_copy_map($incoming_map)
        } elsif ($incoming_map->isdeleted) {
            $incoming_map = $editor->delete_asset_copy_tag_copy_map($incoming_map)
        }
    
    }

    return undef;
}

sub update_copy {
    my($class, $editor, $override, $vol, $copy, $retarget_holds, $force_delete_empty_bib) = @_;

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

    # Duplicated check from create_copy in case a copy template with a deleted location is applied later
    my $copy_loc = $editor->search_asset_copy_location(
        { id => $copy->location, deleted => 'f' } );
        
    return OpenILS::Event->new('COPY_LOCATION_NOT_FOUND') unless @$copy_loc;
    
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

# TODO: get Booking.pm to use this shared method
sub fetch_copies_by_ids {
    my ($class, $e, $copy_ids) = @_;
    my $results = $e->search_asset_copy([
        {id => $copy_ids},
        {flesh => 1, flesh_fields => {acp => ['call_number']}}
    ]);
    return $results if ref($results) eq 'ARRAY';
    return [];
}

# this does the actual work
sub update_fleshed_copies {
    my($class, $editor, $override, $vol, $copies, $delete_stats, $retarget_holds, $force_delete_empty_bib, $create_parts) = @_;
    
    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

    my $evt;

    my %cache;
    $cache{$vol->id} = $vol if $vol;

    sub process_copy {
        my ($original_copy, $cache_ref, $editor, $class, $logger) = @_;

        my $copyid = $original_copy->id;
        $logger->info("vol-update: inspecting copy $copyid");

        my $vol = $cache_ref->{$original_copy->call_number};
        if (!defined $vol) {
            $vol = $editor->retrieve_asset_call_number($original_copy->call_number);
            return (undef, $editor->event) unless defined $vol;
            $cache_ref->{$original_copy->call_number} = $vol;
        }
        return (undef, $editor->event) unless $editor->allowed('UPDATE_COPY', $class->copy_perm_org($vol, $original_copy));

        return ($vol, undef); # return vol and undef if all checks pass
    }

    my $original_copies = $class->fetch_copies_by_ids( $editor, map { $_->id } @$copies );
    for my $original_copy (@$original_copies) {
        my ($vol, $event) = process_copy($original_copy, \%cache, $editor, $class, $logger);
        return $event if $event;
    }

    for my $copy (@$copies) {
        my ($vol, $event) = process_copy($copy, \%cache, $editor, $class, $logger);
        return $event if $event;

        $copy->editor($editor->requestor->id);
        $copy->edit_date('now');

        $copy->status( $copy->status->id ) if ref($copy->status);
        $copy->location( $copy->location->id ) if ref($copy->location);
        $copy->circ_lib( $copy->circ_lib->id ) if ref($copy->circ_lib);
        
        my $parts = $copy->parts;
        $copy->clear_parts;

        my $sc_entries = $copy->stat_cat_entries;
        $copy->clear_stat_cat_entries;

        my $notes = $copy->notes;
        $copy->clear_notes;

        my $tags = $copy->tags;
        $copy->clear_tags;

        my $copy_alerts = $copy->copy_alerts;
        $copy->clear_copy_alerts;

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
        $evt = $class->update_copy_parts($editor, $copy, $delete_stats, $create_parts);

        $copy->notes( $notes );
        $evt = $class->update_copy_notes($editor, $copy);

        $copy->tags( $tags );
        $evt = $class->update_copy_tags($editor, $copy);

        $copy->copy_alerts( $copy_alerts );
        $evt = $class->update_copy_alerts($editor, $copy);

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

    # Cancel any open transits for this copy
    my $transits = $editor->search_action_transit_copy(
        { target_copy=>$copy->id, dest_recv_time => undef, cancel_time => undef } );

    for my $t (@$transits) {
        $t->cancel_time('now');
        $editor->update_action_transit_copy($t)
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

        # Update our copy of the hold to pick up the cancel_time
        # before we pass it off to A/T.
        $hold = $editor->retrieve_action_hold_request($hold->id);

        # tell A/T the hold was cancelled.  Don't wait for a response..
        my $at_ses = OpenSRF::AppSession->create('open-ils.trigger');
        $at_ses->request(
            'open-ils.trigger.event.autocreate',
            'hold_request.cancel.expire_no_target', 
            $hold, $hold->pickup_lib);
    }

    return undef;
}

sub test_perm_against_original_owning_lib {
    my($class, $editor, $perm, $vid) = @_;
    my $vol = $editor->retrieve_asset_call_number($vid) or return $editor->event;
    return $editor->die_event unless $editor->allowed($perm, $vol->owning_lib);
    return 1;
}

sub create_volume {
    my($class, $override, $editor, $vol) = @_;
    my $evt;

    return (undef, $evt) if ( $evt = $class->org_cannot_have_vols($editor, $vol->owning_lib) );

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

   # see if the record this volume references is marked as deleted
   my $rec = $editor->retrieve_biblio_record_entry($vol->record)
      or return $editor->die_event;

    return (
        undef, 
        OpenILS::Event->new('BIB_RECORD_DELETED', rec => $rec->id)
    ) if $U->is_true($rec->deleted);

    # first lets see if there are any collisions
    my $vols = $editor->search_asset_call_number( { 
            owning_lib  => $vol->owning_lib,
            record      => $vol->record,
            label           => $vol->label,
            prefix          => $vol->prefix,
            suffix          => $vol->suffix,
            deleted     => 'f'
        }
    );

    my $label = undef;
    my $labelexists = undef;
    if(@$vols) {
      # we've found an exising volume
        if($override->{all} || grep { $_ eq 'VOLUME_LABEL_EXISTS' } @{$override->{events}}) {
            $label = $vol->label;
            $labelexists = 1;
        } else {
            return (
                undef, 
                OpenILS::Event->new('VOLUME_LABEL_EXISTS', payload => $vol->id)
            );
        }
    }

    # create a temp label so we can create the new volume, 
    # then de-dup it with the existing volume
    $vol->label( "__SYSTEM_TMP_$$".time) if $labelexists;

    $vol->creator($editor->requestor->id);
    $vol->create_date('now');
    $vol->editor($editor->requestor->id);
    $vol->edit_date('now');
    $vol->clear_id;

    $editor->create_asset_call_number($vol) or return (undef, $editor->die_event);

    if($labelexists) {
        # now restore the label and merge into the existing record
        $vol->label($label);
        return OpenILS::Application::Cat::Merge::merge_volumes($editor, [$vol], $$vols[0]);
    }

    return ($vol);
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
    return (undef, $e->die_event) unless $e->allowed('CREATE_VOLUME', $org_id);

    $vol = Fieldmapper::asset::call_number->new;
    $vol->owning_lib($org_id);
    $vol->label_class($label_class) if ($label_class);
    $vol->label($label);
    $vol->prefix($prefix);
    $vol->suffix($suffix);
    $vol->record($record_id);

    return $class->create_volume(0, $e, $vol);
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

        # check for any holds on the title and alert the user before plowing ahead
        if( OpenILS::Application::Cat::BibCommon->title_has_holds($editor, $vol->record) ) {
            return OpenILS::Event->new('TITLE_HAS_HOLDS', payload => $vol->record )
                if not ($override->{all} || grep { $_ eq 'TITLE_HAS_HOLDS' } @{$override->{events}}) and not $force_delete_empty_bib;
        }

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
    my ($class, $e, $copy_id) = @_;

    return $class->set_item_lost_or_lod(
        $e, $copy_id,
        perm => 'SET_CIRC_LOST',
        status => OILS_COPY_STATUS_LOST,
        alt_status => 16, #Long Overdue,
        ous_proc_fee => OILS_SETTING_LOST_PROCESSING_FEE,
        ous_void_od => OILS_SETTING_VOID_OVERDUE_ON_LOST,
        bill_type => 3,
        bill_fee_type => 4,
        bill_note => 'Lost Materials',
        bill_fee_note => 'Lost Materials Processing Fee',
        event => 'COPY_MARKED_LOST',
        stop_fines => OILS_STOP_FINES_LOST,
        at_hook => 'lost'
    );
}

sub set_item_long_overdue {
    my ($class, $e, $copy_id) = @_;

    return $class->set_item_lost_or_lod(
        $e, $copy_id,
        perm => 'SET_CIRC_LONG_OVERDUE',
        status => 16, # Long Overdue
        alt_status => OILS_COPY_STATUS_LOST,
        ous_proc_fee => 'circ.longoverdue_materials_processing_fee',
        ous_void_od => 'circ.void_overdue_on_longoverdue',
        bill_type => 10,
        bill_fee_type => 11,
        bill_note => 'Long Overdue Materials',
        bill_fee_note => 'Long Overdue Materials Processing Fee',
        event => 'COPY_MARKED_LONG_OVERDUE',
        stop_fines => 'LONGOVERDUE',
        at_hook => 'longoverdue'
    );
}

# LOST or LONGOVERDUE
# basic process is the same.  details change.
sub set_item_lost_or_lod {
    my ($class, $e, $copy_id, %args) = @_;

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

    $e->allowed($args{perm}, $circ->circ_lib) or return $e->die_event;

    return $e->die_event(OpenILS::Event->new($args{event}))
	    if ($copy->status == $args{status} || $copy->status == $args{alt_status});

    # ---------------------------------------------------------------------
    # fetch the related org settings
    my $proc_fee = $U->ou_ancestor_setting_value(
        $owning_lib, $args{ous_proc_fee}, $e) || 0;
    my $void_overdue = $U->ou_ancestor_setting_value(
        $owning_lib, $args{ous_void_od}, $e) || 0;

    # ---------------------------------------------------------------------
    # move the copy into LOST status
    $copy->status($args{status});
    $copy->editor($e->requestor->id);
    $copy->edit_date('now');
    $e->update_asset_copy($copy) or return $e->die_event;

    my $price = $U->get_copy_price($e, $copy, $copy->call_number);

    if( $price > 0 ) {
        my $evt = OpenILS::Application::Circ::CircCommon->create_bill($e, 
            $price, $args{bill_type}, $args{bill_note}, $circ->id);
        return $evt if $evt;
    }

    # ---------------------------------------------------------------------
    # if there is a processing fee, charge that too
    if( $proc_fee > 0 ) {
        my $evt = OpenILS::Application::Circ::CircCommon->create_bill($e, 
            $proc_fee, $args{bill_fee_type}, $args{bill_fee_note}, $circ->id);
        return $evt if $evt;
    }

    # ---------------------------------------------------------------------
    # mark the circ as lost and stop the fines
    $circ->stop_fines($args{stop_fines});
    $circ->stop_fines_time('now') unless $circ->stop_fines_time;
    $e->update_action_circulation($circ) or return $e->die_event;

    # ---------------------------------------------------------------------
    # zero out overdue fines on this circ if configured
    if( $void_overdue ) {
        my $evt = OpenILS::Application::Circ::CircCommon->void_or_zero_overdues($e, $circ, {force_zero => 1, note => "System: OVERDUE REVERSED for " . $args{bill_note} . " Processing"});
        return $evt if $evt;
    }

    my $evt = OpenILS::Application::Circ::CircCommon->reopen_xact($e, $circ->id);
    return $evt if $evt;

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    $ses->request(
        'open-ils.trigger.event.autocreate', 
        $args{at_hook}, $circ, $circ->circ_lib
    );

    my $evt2 = OpenILS::Utils::Penalty->calculate_penalties(
        $e, $circ->usr, $U->xact_org($circ->id, $e));
    return $evt2 if $evt2;

    return undef;
}
