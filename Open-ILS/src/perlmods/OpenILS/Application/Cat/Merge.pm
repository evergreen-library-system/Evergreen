use strict; use warnings;
package OpenILS::Application::Cat::Merge;
use base qw/OpenSRF::Application/;
use OpenSRF::Application;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Cat::Utils;
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

	my $vol;
	my $evt;

	my %r = map { $_ => 1 } ($master, @$records); # unique the ids
	my @recs = keys %r;

	my $reqr = $editor->requestor;
	$logger->activity("merge: user ".$reqr->id." merging bib records: @recs");

	# -----------------------------------------------------------
	# collect all of the volumes, merge any with duplicate 
	# labels, then move all of the volumes to the master record
	# -----------------------------------------------------------
	my @volumes;
	for (@recs) {
		my $vs = $editor->search_asset_call_number({record => $_});
		push( @volumes, @$vs );
	}

	$logger->info("merge: merge recovered ".scalar(@volumes)." total volumes");

	my @trimmed;
	# de-duplicate any volumes with the same label and owning_lib
	for my $v (@volumes) {
		my $l = $v->label;
		my $o = $v->owning_lib;
		my @dups = rgrep( 
			sub { $_->label eq $l and $_->owning_lib == $o }, \@volumes );

		if( @dups == 1 ) {
			push( @trimmed, @dups );

		} else {
			my($vol, $e) = merge_volumes($editor, \@dups);
			return $e if $e;
			push(@trimmed, $vol);
		}
	}


	# make all the volumes point to the master record
	my $stat;
	for $vol (@trimmed) {
		if( $vol->record ne $master ) {

			$logger->debug("merge: moving volume ".
				$vol->id." from record ".$vol->record. " to $master");

			$vol->record( $master );
			$editor->update_asset_call_number(
				$vol, { 
					permorg => $vol->owning_lib, 
					checkperm => 1 
				}
			) or return $editor->event;
		}
	}

	# cycle through and delete the non-master records
	for my $rec (@recs) {

		my ($record, $evt) = 
			$editor->retrieve_biblio_record_entry($rec);
		return $evt if $evt;

		$logger->debug("merge: seeing if record $rec needs to be deleted or un-deleted");

		if( $rec == $master ) {
			# make sure the master record is not deleted
			if( $record->deleted and $record->deleted ne 'f' ) {
				$logger->info("merge: master record is marked as deleted...un-deleting.");
				$record->deleted('f');
				$record->editor($reqr->id);
				$record->edit_date('now');
				$editor->update_biblio_record_entry($record, {checkperm => 1})
					or return $editor->event;
			}

		} else {
			$logger->info("merge: deleting record $rec");
			$record->deleted('t');
			$record->editor($reqr->id);
			$record->edit_date('now');
			$editor->update_biblio_record_entry($record, {checkperm => 1})
				or return $editor->event;
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

	return ($$volumes[0]) if(scalar(@$volumes) == 1);

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

	$logger->info("merge: merge using volume $bigcn as the master");

	# now move all of the copies to the new volume
	for my $cn (keys %copies) {
		next if $cn == $bigcn;
		for my $copy (@{$copies{$cn}}) {
			$logger->debug("merge: setting call_number to $bigcn for copy ".$copy->id);
			$copy->call_number($bigcn);
			$copy->editor($editor->requestor->id);
			$copy->edit_date('now');
			$editor->update_asset_copy($copy, {checkperm=>1})
				or return (undef, $editor->event);
		}
	}

	for( @$volumes ) {
		next if $_->id == $bigcn;
		$logger->debug("merge: marking call_number as deleted: ".$_->id);
		$_->deleted('t');
		$_->editor($editor->requestor->id);
		$_->edit_date('now');
		$editor->update_asset_call_number($_,{checkperm=>1});
			return (undef, $editor->event);
	}

	my ($mvol) = grep { $_->id == $bigcn } @$volumes;
	$logger->debug("merge: returning master volume ".$mvol->id);
	return ($mvol);
}


1;


