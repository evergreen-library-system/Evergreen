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


# takes a master record and a list of 
# sub-records to merge into the master record
sub merge_records {
	my( $editor, $master, $records ) = @_;

	my $reqr = $editor->requestor;
	my @recs = @$records;
	$logger->activity("merge: user ".$reqr->id." merging bib records: @recs");

	my $vol;
	my $evt;

	# -----------------------------------------------------------
	# collect all of the volumes, merge any with duplicate 
	# labels, then move all of the volumes to the master record
	# -----------------------------------------------------------
	my @volumes;
	for (($master, @recs)) {
		my $vs = $editor->search_asset_call_number({record => $_});
		push( @volumes, @$vs );
	}

	$logger->info("merge: merge recovered ".scalar(@volumes)." total volumes");

	my %volumes;
	for (@volumes) {
		$logger->debug("merge: loaded volume ".$_->id);
		$volumes{$_->label}++ if $volumes{$_->label};
		$volumes{$_->label} = 1 unless $volumes{$_->label};
	}

	# deduplicate volumes
	my @trimmed;
	for my $label (keys %volumes) {

		if( $volumes{$label} == 1 ) {
			my ($v) = grep { $_->label eq $label } @volumes;
			push( @trimmed, $v );

		} else {

			$logger->debug("merge: found duplicate CN label $label");
			($vol, $evt) = merge_volumes( $editor,
				[grep { $_->label eq $label } @volumes ]);
			return $evt if $evt;
			push( @trimmed, $vol );
		}
	}

	# make all the volumes point to the master record
	my $stat;
	for $vol (@trimmed) {
		if( $vol->record ne $master ) {
			$vol->record( $master );
			$evt = $editor->update_asset_call_number(
				$vol, { 
					org => $vol->owning_lib, 
					checkperm => 1 
				}
			);
			return $evt if $evt;
		}
	}

	# cycle through and delete the non-master records
	for my $rec (@recs) {
		next if $rec == $master;
		my ($record, $evt) = 
			$editor->retrieve_biblio_record_entry($rec);
		return $evt if $evt;
		$record->deleted('t');
		$evt = $editor->update_biblio_record_entry(
			$record, { checkperm => 1 });
		return $evt if $evt;
	}

	return undef;
}



# takes a list of volume objects, picks the volume with most
# copies and moves all copies attached to the other volumes
# into said volume.  all other volumes are deleted
sub merge_volumes {
	my( $editor, $volumes ) = @_;
	my %copies;
	my $evt;

	return ($$volumes[0]) if(scalar(@$volumes) == 1);

	$logger->debug("merge: fetching copies for volume list of size ".scalar(@$volumes));

	# collect all of the copies attached to the selected volumes
	for( @$volumes ) {
		$copies{$_->id} = $editor->search_asset_copy({call_number=>$_->id});
	}

	# find the CN with the most copies and make it the master CN
	my $big = 0;
	my $bigcn;
	for my $cn (keys %copies) {
		my $count = scalar(@{$copies{$cn}});
		if( $count > $big ) {
			$big = $count;
			$bigcn = $cn;
		}
	}

	$logger->info("merge: merge using volume $bigcn as the master");

	# now move all of the copies to the new volume
	for my $cn (keys %copies) {
		next if $cn == $bigcn;
		for my $copy (@{$copies{$cn}}) {
			$logger->debug("merge: setting call_number to $bigcn for copy ".$copy->id);
			$copy->call_number($bigcn);
			$evt = $editor->update_asset_copy($copy, {checkperm=>1});
			return (undef, $evt) if $evt;
		}
	}

	for( @$volumes ) {
		next if $_->id == $bigcn;
		$logger->debug("merge: marking call_number as deleted: ".$_->id);
		$_->deleted('t');
		$evt = $editor->update_asset_call_number($_,{checkperm=>1});
		return (undef, $evt) if $evt;
	}

	my ($mvol) = grep { $_->id == $bigcn } @$volumes;
	$logger->debug("merge: returning master volume ".$mvol->id);
	return ( $mvol, undef );
}


1;


