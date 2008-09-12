use strict; use warnings;
package OpenILS::Application::Cat::Merge;
use base qw/OpenILS::Application/;
use OpenSRF::Application;
use OpenILS::Application::AppUtils;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;
use OpenSRF::Utils::Logger qw($logger);
use Data::Dumper;
my $U = "OpenILS::Application::AppUtils";

my $storage;


# removes items from an array and returns the removed items
# example : my @d = rgrep(sub { $_ =~ /o/ }, \@a);
# there's surely a smarter way to do this
sub rgrep {
   my( $sub, $arr ) = @_;
   my @del;
   for( my $i = 0; $i < @$arr; $i++ ) {
      my $a = $$arr[$i];
      local $_ = $a;
      if($sub->()) {
         splice(@$arr, $i--, 1);
         push( @del, $a );
      }
   }
   return @del;
}



# takes a master record and a list of 
# sub-records to merge into the master record
sub merge_records {
	my( $editor, $master, $records ) = @_;

    # bib records are global objects, so no org context required.
    return (undef, $editor->die_event) 
        unless $editor->allowed('MERGE_BIB_RECORDS');

	my $vol;
	my $evt;

	my %r = map { $_ => 1 } ($master, @$records); # unique the ids
	my @recs = keys %r;

	my $reqr = $editor->requestor;
	$logger->activity("merge: user ".$reqr->id." merging bib records: @recs with master = $master");

	# -----------------------------------------------------------
	# collect all of the volumes, merge any with duplicate 
	# labels, then move all of the volumes to the master record
	# -----------------------------------------------------------
	my @volumes;
	for (@recs) {
		my $vs = $editor->search_asset_call_number({record => $_, deleted=>'f'});
		push( @volumes, @$vs );
	}

	$logger->info("merge: merge recovered ".scalar(@volumes)." total volumes");

	my @trimmed;
	# de-duplicate any volumes with the same label and owning_lib

	my %seen_vols;

	for my $v (@volumes) {
		my $l = $v->label;
		my $o = $v->owning_lib;

		if($seen_vols{$v->id}) {
			$logger->debug("merge: skipping ".$v->id." since it's already been merged");
			next;
		}

		$seen_vols{$v->id} = 1;

		$logger->debug("merge: [".$v->id."] looking for dupes with label $l and owning_lib $o");

		my @dups;
		for my $vv (@volumes) {
			if( $vv->label eq $v->label and $vv->owning_lib == $v->owning_lib ) {
				$logger->debug("merge: pushing dupe volume ".$vv->id) if @dups;
				push( @dups, $vv );
				$seen_vols{$vv->id} = 1;
			} 
		}

		if( @dups == 1 ) {
			$logger->debug("merge: pushing unique volume into trimmed volume set: ".$v->id);
			push( @trimmed, @dups );

		} else {
			my($vol, $e) = merge_volumes($editor, \@dups);
			return $e if $e;
			$logger->debug("merge: pushing vol-merged volume into trimmed volume set: ".$vol->id);
			push(@trimmed, $vol);
		}
	}

	my $s = 'merge: trimmed volume set contains the following vols: ';
	$s .= 'id = '.$_->id .' : record = '.$_->record.' | ' for @trimmed;
	$logger->debug($s);

	# make all the volumes point to the master record
	my $stat;
	for $vol (@trimmed) {
		if( $vol->record ne $master ) {

			$logger->debug("merge: moving volume ".
				$vol->id." from record ".$vol->record. " to $master");

			$vol->editor( $editor->requestor->id );
			$vol->edit_date('now');
			$vol->record( $master );
			$editor->update_asset_call_number($vol)
				or return $editor->die_event;
		}
	}

	# cycle through and delete the non-master records
	for my $rec (@recs) {

		my $record = $editor->retrieve_biblio_record_entry($rec)
            or return $editor->die_event;

		$logger->debug("merge: seeing if record $rec needs to be deleted or un-deleted");

		if( $rec == $master ) {
			# make sure the master record is not deleted
			if( $U->is_true($record->deleted) ) {
				$logger->info("merge: master record is marked as deleted...un-deleting.");
				$record->deleted('f');
				$record->editor($reqr->id);
				$record->edit_date('now');
				$editor->update_biblio_record_entry($record)
					or return $editor->die_event;
			}

		} else {
			$logger->info("merge: deleting record $rec");
			$record->deleted('t');
			$record->editor($reqr->id);
			$record->edit_date('now');
			$editor->update_biblio_record_entry($record)
				or return $editor->die_event;
		}
	}

	return undef;
}



# takes a list of volume objects, picks the volume with most
# copies and moves all copies attached to the other volumes
# into said volume.  all other volumes are deleted
sub merge_volumes {
	my( $editor, $volumes, $master ) = @_;
	my %copies;
	my $evt;

	return ($$volumes[0]) if !$master and @$volumes == 1;

	return ($$volumes[0]) if 
		$master and @$volumes == 1 
		and $master->id == $$volumes[0]->id;

	$logger->debug("merge: fetching copies for volume list of size ".scalar(@$volumes));

	# collect all of the copies attached to the selected volumes
	for( @$volumes ) {
		$copies{$_->id} = $editor->search_asset_copy({call_number=>$_->id, deleted=>'f'});
		$logger->debug("merge: found ".scalar(@{$copies{$_->id}})." copies for volume ".$_->id);
	}
	
	my $bigcn;
	if( $master ) {

		# the caller has chosen the master record
		$bigcn = $master->id;
		push( @$volumes, $master );

	} else {

		# find the CN with the most copies and make it the master CN
		my $big = 0;
		for my $cn (keys %copies) {
			my $count = scalar(@{$copies{$cn}});
			if( $count > $big ) {
				$big = $count;
				$bigcn = $cn;
			}
		}
	}

	$bigcn = $$volumes[0]->id unless $bigcn;

	$logger->info("merge: merge using volume $bigcn as the master");

	# now move all of the copies to the new volume
	for my $cn (keys %copies) {
		next if $cn == $bigcn;
		for my $copy (@{$copies{$cn}}) {
			$logger->debug("merge: setting call_number to $bigcn for copy ".$copy->id);
			$copy->call_number($bigcn);
			$copy->editor($editor->requestor->id);
			$copy->edit_date('now');
			$editor->update_asset_copy($copy) or return (undef, $editor->die_event);
		}
	}

	for( @$volumes ) {
		next if $_->id == $bigcn;
		$logger->debug("merge: marking call_number as deleted: ".$_->id);
		$_->deleted('t');
		$_->editor($editor->requestor->id);
		$_->edit_date('now');
		$editor->update_asset_call_number($_) or return (undef, $editor->die_event);
        merge_volume_holds($editor, $bigcn, $_->id);
	}

	my ($mvol) = grep { $_->id == $bigcn } @$volumes;
	$logger->debug("merge: returning master volume ".$mvol->id);
	return ($mvol);
}

sub merge_volume_holds {
    my($e, $master_id, $vol_id) = @_;

    my $holds = $e->search_action_hold_request(
        {   cancel_time => undef, 
            fulfillment_time => undef,
            hold_type => 'V',
            target => $vol_id
        }
    );

    for my $hold (@$holds) {

        $logger->info("Changing hold ".$hold->id.
            " target from ".$hold->target." to $master_id in volume merge");

        $hold->target($master_id);
        unless($e->update_action_hold_request($hold)) {
            my $evt = $e->event;
            $logger->error("Error updating hold ". $evt->textcode .":". $evt->desc .":". $evt->stacktrace); 
        }
    }

    return undef;
}


1;


