# ---------------------------------------------------------------
# Copyright (C) 2005  Georgia Public Library Service 
# Bill Erickson <highfalutin@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

package OpenILS::Application::Circ::Rules;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenILS::EX;
use OpenSRF::Utils::Logger qw(:level); 

use Template qw(:template);
use Template::Stash; 

use Time::HiRes qw(time);
use OpenILS::Utils::ModsParser;

use OpenSRF::Utils;
use OpenSRF::EX qw(:try);

use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
use Digest::MD5 qw(md5_hex);

my $log = "OpenSRF::Utils::Logger";

# ----------------------------------------------------------------
# rules scripts
my $circ_script;
my $permission_script;
my $duration_script;
my $recurring_fines_script;
my $max_fines_script;
my $permit_hold_script;
my $permit_renew_script;
# ----------------------------------------------------------------


# data used for this circulation transaction
my $circ_objects = {};

# some static data from the database
my $copy_statuses;
my $patron_standings;
my $patron_profiles;
my $shelving_locations;

# template stash
my $stash;

# memcache for caching the circ objects
my $cache_handle;


use constant NO_COPY => 100;

sub initialize {

	my $self = shift;
	my $conf = OpenSRF::Utils::SettingsClient->new;

	# ----------------------------------------------------------------
	# set up the rules scripts
	# ----------------------------------------------------------------
	$circ_script = $conf->config_value(					
		"apps", "open-ils.circ","app_settings", "rules", "main");

	$permission_script = $conf->config_value(			
		"apps", "open-ils.circ","app_settings", "rules", "permission");

	$duration_script = $conf->config_value(			
		"apps", "open-ils.circ","app_settings", "rules", "duration");

	$recurring_fines_script = $conf->config_value(	
		"apps", "open-ils.circ","app_settings", "rules", "recurring_fines");

	$max_fines_script = $conf->config_value(			
		"apps", "open-ils.circ","app_settings", "rules", "max_fines");

	$permit_hold_script = $conf->config_value(
		"apps", "open-ils.circ","app_settings", "rules", "permit_hold");

	$permit_renew_script = $conf->config_value(
		"apps", "open-ils.circ","app_settings", "rules", "permit_renew");

	$log->debug("Loaded rules scripts for circ:\n".
		"main - $circ_script : permit circ - $permission_script\n".
		"duration - $duration_script : recurring - $recurring_fines_script\n".
		"max fines - $max_fines_script : permit hold - $permit_hold_script", DEBUG);


	$cache_handle = OpenSRF::Utils::Cache->new();
}


sub _grab_patron_standings {
	my $session = shift;
	if(!$patron_standings) {
		my $standing_req = $session->request(
			"open-ils.storage.direct.config.standing.retrieve.all.atomic");
		$patron_standings = $standing_req->gather(1);
		$patron_standings =
			{ map { (''.$_->id => $_->value) } @$patron_standings };
	}
}

sub _grab_patron_profiles {
	my $session = shift;
	if(!$patron_profiles) {
		my $profile_req = $session->request(
			"open-ils.storage.direct.actor.profile.retrieve.all.atomic");
		$patron_profiles = $profile_req->gather(1);
		$patron_profiles =
			{ map { (''.$_->id => $_->name) } @$patron_profiles };
	}

}

sub _grab_user {
	my $session = shift;
	my $patron_id = shift;
	my $patron_req	= $session->request(
		"open-ils.storage.direct.actor.user.retrieve", 
		$patron_id );
	return $patron_req->gather(1);
}
	

sub _grab_title_by_copy {
	my $session = shift;
	my $copyid = shift;
	my $title_req	= $session->request(
		"open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy",
		$copyid );
	return $title_req->gather(1);
}

sub _grab_patron_summary {
	my $session = shift;
	my $patron_id = shift;
	my $summary_req = $session->request(
		"open-ils.storage.action.circulation.patron_summary",
		$patron_id );
	return $summary_req->gather(1);
}

sub _grab_copy_by_barcode {
	my($session, $barcode) = @_;
	warn "Searching for copy with barcode $barcode\n";
	my $copy_req	= $session->request(
		"open-ils.storage.fleshed.asset.copy.search.barcode", 
		$barcode );
	return $copy_req->gather(1);
}

sub _grab_copy_by_id {
	my($session, $id) = @_;
	warn "Searching for copy with id $id\n";
	my $copy_req	= $session->request(
		"open-ils.storage.direct.asset.copy.retrieve", 
		$id );
	my $c = $copy_req->gather(1);
	if($c) { return _grab_copy_by_barcode($session, $c->barcode); }
	return undef;
}


sub gather_hold_objects {
	my($session, $hold, $copy, $args) = @_;

	_grab_patron_standings($session);
	_grab_patron_profiles($session);


	# flesh me
	$copy = _grab_copy_by_barcode($session, $copy->barcode);

	my $hold_objects = {};
	$hold_objects->{standings} = $patron_standings;
	$hold_objects->{copy}		= $copy;
	$hold_objects->{hold}		= $hold;
	$hold_objects->{title}		= $$args{title} || _grab_title_by_copy($session, $copy->id);
	$hold_objects->{requestor} = _grab_user($session, $hold->requestor);
	my $patron						= _grab_user($session, $hold->usr);

	$copy->status( $copy->status->name );
	$patron->standing($patron_standings->{$patron->standing()});
	$patron->profile( $patron_profiles->{$patron->profile});

	$hold_objects->{patron}		= $patron;

	return $hold_objects;
}



__PACKAGE__->register_method(
	method	=> "permit_hold",
	api_name	=> "open-ils.circ.permit_hold",
	notes		=> <<"	NOTES");
	Determines whether a given copy is eligible to be held
	NOTES

sub permit_hold {
	my( $self, $client, $hold, $copy, $args ) = @_;

	my $session	= OpenSRF::AppSession->create("open-ils.storage");
	
	# collect items necessary for circ calculation
	my $hold_objects = gather_hold_objects( $session, $hold, $copy, $args );

	$stash = Template::Stash->new(
			circ_objects			=> $hold_objects,
			result					=> []);

	$stash->set("run_block", $permit_hold_script);

	# grab the number of copies checked out by the patron as
	# well as the total fines
	my $summary = _grab_patron_summary($session, $hold_objects->{patron}->id);
	$summary->[0] ||= 0;
	$summary->[1] ||= 0.0;

	$stash->set("patron_copies", $summary->[0] );
	$stash->set("patron_fines", $summary->[1] );

	# run the permissibility script
	run_script();
	my $result = $stash->get("result");

	# 0 means OK in the script
	return 1 if($result->[0] == 0);
	return 0;

}





# ----------------------------------------------------------------
# Collect all of the objects necessary for calculating the
# circ matrix.
# ----------------------------------------------------------------
sub gather_circ_objects {
	my( $session, $barcode_string, $patron_id, $copy ) = @_;

	throw OpenSRF::EX::ERROR 
		("gather_circ_objects needs data")
			unless ($barcode_string and $patron_id);

	warn "Gathering circ objects with barcode $barcode_string and patron id $patron_id\n";

	# see if all of the circ objects are in cache
#	my $cache_key =  "circ_object_" . md5_hex( $barcode_string, $patron_id );
#	$circ_objects = $cache_handle->get_cache($cache_key);

#	if($circ_objects) { 
#		$stash = Template::Stash->new(
#			circ_objects			=> $circ_objects,
#			result					=> [],
#			target_copy_status	=> 1,
#			);
#		return;
#	}

	# only necessary if the circ objects have not been built yet

	_grab_patron_standings($session);
	_grab_patron_profiles($session);


	if(!$copy) {
		$copy = _grab_copy_by_barcode($session, $barcode_string);
		if(!$copy) { return NO_COPY; }
	}

	my $patron = _grab_user($session, $patron_id);

	$copy->status( $copy->status->name );
	$circ_objects->{copy} = $copy;

	$patron->standing($patron_standings->{$patron->standing()});
	$patron->profile( $patron_profiles->{$patron->profile});
	$circ_objects->{patron} = $patron;
	$circ_objects->{standings} = $patron_standings;

	#$circ_objects->{title} = $title_req->gather(1);
	$circ_objects->{title} = _grab_title_by_copy($session, $circ_objects->{copy}->id);
#	$cache_handle->put_cache( $cache_key, $circ_objects, 30 );

	$stash = Template::Stash->new(
			circ_objects			=> $circ_objects,
			result					=> [],
			target_copy_status	=> 1,
			);
}



sub run_script {

	my $result;

	my $template = Template->new(
		{ 
			STASH			=> $stash,
			ABSOLUTE		=> 1, 
			OUTPUT		=> \$result,
		}
	);

	my $status = $template->process($circ_script);

	if(!$status) { 
		throw OpenSRF::EX::ERROR 
			("Error processing circ script " .  $template->error()); 
	}

	warn "Script result: $result\n";
}




__PACKAGE__->register_method(
	method	=> "permit_circ",
	api_name	=> "open-ils.circ.permit_checkout",
);

sub permit_circ {
	my( $self, $client, $user_session, $barcode, $user_id, $outstanding_count ) = @_;

	my $copy_status_mangled;
	my $hold;

	my $renew = 0;
	if(defined($outstanding_count) && $outstanding_count eq "renew") {
		$renew = 1;
		$outstanding_count = 0;
	} else { $outstanding_count ||= 0; }

	my $session	= OpenSRF::AppSession->create("open-ils.storage");
	
	# collect items necessary for circ calculation
	my $status = gather_circ_objects( $session, $barcode, $user_id );

	if( $status == NO_COPY ) {
		return { record => undef, 
			status => NO_COPY, 
			text => "No copy available with barcode $barcode"
		};
	}

	my $copy = $stash->get("circ_objects")->{copy};

	warn "Found copy in permit: " . $copy->id . "\n";

	warn "Copy status in checkout is " . $stash->get("circ_objects")->{copy}->status . "\n";

	$stash->set("run_block", $permission_script);

	# grab the number of copies checked out by the patron as
	# well as the total fines
	my $summary_req = $session->request(
		"open-ils.storage.action.circulation.patron_summary",
		$stash->get("circ_objects")->{patron}->id );

	my $summary = $summary_req->gather(1);

	$summary->[0] ||= 0;
	$summary->[1] ||= 0.0;

	$stash->set("patron_copies", $summary->[0]  + $outstanding_count );
	$stash->set("patron_fines", $summary->[1] );
	$stash->set("renew", 1) if $renew; 

	# run the permissibility script
	run_script();

	my $arr = $stash->get("result");

	if( $arr->[0]  eq "0" ) { # and $copy_status_mangled == 8) {

		# see if this copy is needed to fulfil a hold

		warn "Searching for hold for checkout of copy " . $copy->id . "\n";

		my $hold = $session->request(
			"open-ils.storage.direct.action.hold_request.search.atomic",
			 current_copy =>  $copy->id , fulfillment_time => undef )->gather(1);

		$hold = $hold->[0];

		if($hold) { warn "Found hold in circ permit with id " . $hold->id . "\n"; }

		if($hold) {

			warn "Found unfulfilled hold in permit ". $hold->id . "\n";

			if( $hold->usr eq $user_id ) {
				return { status => 0, text => "OK" };

			} else {
				return { status => 6, 
					text => "Copy is needed by a different user to fulfill a hold" };
			}
		} 
	}
	
	return { status => $arr->[0], text => $arr->[1] };

}



__PACKAGE__->register_method(
	method	=> "circulate",
	api_name	=> "open-ils.circ.checkout.barcode",
);

sub circulate {
	my( $self, $client, $user_session, $barcode, $patron, $isrenew, $numrenews ) = @_;


	my $user = $apputils->check_user_session($user_session);
	my $session = $apputils->start_db_session();

	my $copy =  _grab_copy_by_barcode($session, $barcode);
	my $realstatus = $copy->status->id;

	warn "Checkout copy status is $realstatus\n";

	gather_circ_objects( $session, $barcode, $patron, $copy );

	# grab the copy statuses if we don't already have them
	if(!$copy_statuses) {
		my $csreq = $session->request(
			"open-ils.storage.direct.config.copy_status.retrieve.all.atomic" );
		$copy_statuses = $csreq->gather(1);
	}

	# put copy statuses into the stash
	$stash->set("copy_statuses", $copy_statuses );

	$copy = $circ_objects->{copy};
	my ($circ, $duration, $recurring, $max) =  run_circ_scripts($session);


	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = 
		gmtime(OpenSRF::Utils->interval_to_seconds($circ->duration) + int(time()));
	$year += 1900; $mon += 1;
	my $due_date = sprintf(
   	'%s-%0.2d-%0.2dT%s:%0.2d:%0.s2-00',
   	$year, $mon, $mday, $hour, $min, $sec);

	warn "Setting due date to $due_date\n";
	$circ->due_date($due_date);
	$circ->circ_lib($user->home_ou);

	if($isrenew) {
		warn "Renewing circ.... ".$circ->id ." and setting num renews to " . $numrenews - 1 . "\n";
		$circ->renewal(1);
		$circ->clear_id;
		$circ->renewal_remaining($numrenews - 1);
	}


	# commit new circ object to db
	my $commit = $session->request(
		"open-ils.storage.direct.action.circulation.create", $circ );
	my $id = $commit->gather(1);

	if(!$id) {
		throw OpenSRF::EX::ERROR 
			("Error creating new circulation object");
	}

	# update the copy with the new circ
	$copy->status( $stash->get("target_copy_status") );
	$copy->location( $copy->location->id );
	$copy->circ_lib( $copy->circ_lib->id ); #XXX XXX needs to point to the lib that actually checked out the item (user->home_ou)?

	# commit copy to db
	my $copy_update = $session->request(
		"open-ils.storage.direct.asset.copy.update",
		$copy );
	$copy_update->gather(1);


	if( $realstatus eq "8" ) { # on holds shelf


		warn "Searching for hold for checkout of copy " . $copy->id . "\n";

		my $hold = $session->request(
			"open-ils.storage.direct.action.hold_request.search.atomic",
			 current_copy =>  $copy->id , fulfillment_time => undef )->gather(1);
		$hold = $hold->[0];

		if($hold) {

			$hold->fulfillment_time("now");
				my $s = $session->request(
					"open-ils.storage.direct.action.hold_request.update", $hold )->gather(1);
				if(!$s) { throw OpenSRF::EX::ERROR ("Error updating hold");}
		}
	}

	$apputils->commit_db_session($session);

	# remove our circ object from the cache
	$cache_handle->delete_cache("circ_object_" . md5_hex($barcode, $patron));

	# re-retrieve the the committed circ object  
	$circ = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.action.circulation.retrieve",
		$id );


	# push the rules and due date into the circ object
	$circ->duration_rule($duration);
	$circ->max_fine_rule($max);
	$circ->recuring_fine_rule($recurring);

	# turn the biblio record into a friendly object
	my $obj = $stash->get("circ_objects");
	my $u = OpenILS::Utils::ModsParser->new();
	$u->start_mods_batch( $circ_objects->{title}->marc() );
	my $mods = $u->finish_mods_batch();


	return { circ => $circ, copy => $copy, record => $mods };

}



# runs the duration, recurring_fines, and max_fines scripts.
# builds the new circ object based on the rules returned from 
# these scripts. 
# returns (circ, duration_rule, recurring_fines_rule, max_fines_rule)
sub run_circ_scripts {
	my $session = shift;

	# go through all of the scripts and process
	# each script returns 
	# [ rule_name, level (appropriate to the script) ]
	$stash->set("result", [] );
	$stash->set("run_block", $duration_script);
	run_script();
	my $duration_rule = $stash->get("result");

	$stash->set("run_block", $recurring_fines_script);
	$stash->set("result", [] );
	run_script();
	my $rec_fines_rule = $stash->get("result");

	$stash->set("run_block", $max_fines_script);
	$stash->set("result", [] );
	run_script();
	my $max_fines_rule = $stash->get("result");

	my $obj = $stash->get("circ_objects");

	# ----------------------------------------------------------
	# find the rules objects based on the rule names returned from
	# the various scripts.
	my $dur_req = $session->request(
		"open-ils.storage.direct.config.rules.circ_duration.search.name.atomic",
		$duration_rule->[0] );

	my $rec_req = $session->request(
		"open-ils.storage.direct.config.rules.recuring_fine.search.name.atomic",
		$rec_fines_rule->[0] );

	my $max_req = $session->request(
		"open-ils.storage.direct.config.rules.max_fine.search.name.atomic",
		$max_fines_rule->[0] );

	my $duration	= $dur_req->gather(1)->[0];
	my $recurring	= $rec_req->gather(1)->[0];
	my $max			= $max_req->gather(1)->[0];

	my $copy = $circ_objects->{copy};

	use Data::Dumper;
	warn "Building a new circulation object with\n".
		"=> copy "				. Dumper($copy) .
		"=> duration_rule "	. Dumper($duration_rule) .
		"=> rec_files_rule " . Dumper($rec_fines_rule) .
		"=> duration "			. Dumper($duration) .
		"=> recurring "		. Dumper($recurring) .
		"=> max "				. Dumper($max);


	# build the new circ object
	my $circ =  build_circ_object($session, $copy, $duration_rule->[1], 
			$rec_fines_rule->[1], $duration, $recurring, $max );

	return ($circ, $duration, $recurring, $max);

}

# ------------------------------------------------------------------
# Builds a new circ object
# ------------------------------------------------------------------
sub build_circ_object {
	my( $session, $copy, $dur_level, $rec_level, 
			$duration, $recurring, $max ) = @_;

	my $circ = new Fieldmapper::action::circulation;

	$circ->circ_lib( $copy->circ_lib->id() );
	if($dur_level == 1) {
		$circ->duration( $duration->shrt );
	} elsif($dur_level == 2) {
		$circ->duration( $duration->normal );
	} elsif($dur_level == 3) {
		$circ->duration( $duration->extended );
	}

	if($rec_level == 1) {
		$circ->recuring_fine( $recurring->low );
	} elsif($rec_level == 2) {
		$circ->recuring_fine( $recurring->normal );
	} elsif($rec_level == 3) {
		$circ->recuring_fine( $recurring->high );
	}

	$circ->duration_rule( $duration->name );
	$circ->recuring_fine_rule( $recurring->name );
	$circ->max_fine_rule( $max->name );
	$circ->max_fine( $max->amount );

	$circ->fine_interval($recurring->recurance_interval);
	$circ->renewal_remaining( $duration->max_renewals );
	$circ->target_copy( $copy->id );
	$circ->usr( $circ_objects->{patron}->id );

	return $circ;

}

__PACKAGE__->register_method(
	method	=> "transit_receive",
	api_name	=> "open-ils.circ.transit.receive",
	notes		=> <<"	NOTES");
	Receives a copy that is in transit.  
	Params are login_session and copyid.
	Logged in user must have COPY_CHECKIN priveleges.

	status 3 means that this transit is destined for somewhere else
	status 10 means the copy is not in transit
	status 11 means the transit is complete, does not need processing
	status 12 means copy is in transit but no tansit was found

	NOTES

sub transit_receive {
	my( $self, $client, $login_session, $copyid ) = @_;

	my $user = $apputils->check_user_session($login_session);

	if($apputils->check_user_perms($user->id, $user->home_ou, "COPY_CHECKIN")) {
		return OpenILS::Perm->new("COPY_CHECKIN");
	}

	warn "Receiving copy for transit $copyid\n";

	my $session = $apputils->start_db_session();
	my $copy = $session->request(
			"open-ils.storage.direct.asset.copy.retrieve", $copyid)->gather(1);
	my $transit;

	if(!$copy->status eq "6") {
		return { status => 10, route_to => $copy->circ_lib };
	}


	$transit = $session->request(
		"open-ils.storage.direct.action.transit_copy.search_where",
		{ target_copy => $copy->id, dest_recv_time => undef } )->gather(1);


	my $record = _grab_title_by_copy($session, $copy->id);
	my $u = OpenILS::Utils::ModsParser->new();
	$u->start_mods_batch( $record->marc() );
	$record = $u->finish_mods_batch();

	if($transit) {

		warn "Found transit " . $transit->id . " for copy $copyid\n";

		if( defined($transit->dest_recv_time) ) {
			return { status => 11, route_to => $copy->circ_lib, 
				text => "Transit is already complete for this copy" };
		}

		$transit->dest_recv_time("now");
		my $s = $session->request(
			"open-ils.storage.direct.action.transit_copy.update", $transit )->gather(1);

		if(!$s) { throw OpenSRF::EX::ERROR ("Error updating transit " . $transit->id . "\n"); }

		warn "Searching for hold transit with id " . $transit->id . "\n";

		my $holdtransit = $session->request(
			"open-ils.storage.direct.action.hold_transit_copy.retrieve",
			$transit->id )->gather(1);

		if($holdtransit) {

			warn "Found hold transit for copy $copyid\n";

			my $hold = $session->request(
				"open-ils.storage.direct.action.hold_request.retrieve",
				$holdtransit->hold )->gather(1);

			if(!$hold) {
				throw OpenSRF::EX::ERROR ("No hold found to match transit " . $holdtransit->id);
			}

			# put copy on the holds shelf
			$copy->status(8); #hold shelf status
			$copy->editor($user->id); #hold shelf status
			$copy->edit_date("now"); #hold shelf status

			warn "Updating copy " . $copy->id . " with new status, editor, and edit date\n";

			my $s = $session->request(
				"open-ils.storage.direct.asset.copy.update", $copy )->gather(1);
			if(!$s) {throw OpenSRF::EX::ERROR ("Error putting copy on holds shelf ".$copy->id);} # blah..

			$apputils->commit_db_session($session);

			return { status => 4, route_to => "Holds Shelf", 
				text => "Transit Complete", record => $record, copy => $copy  };


		} else {

			if($transit->dest eq $user->home_ou) {

				$copy->status(0); 
				$copy->editor($user->id); 
				$copy->edit_date("now"); 

				my $s = $session->request(
					"open-ils.storage.direct.asset.copy.update", $copy )->gather(1);
				if(!$s) {throw OpenSRF::EX::ERROR ("Error updating copy ".$copy->id);} # blah..

				my($status, $status_text) = (0, "Transit Complete");

				my $circ;
				if($transit->copy_status eq "3") { #if copy is lost
					$status = 2;
					$status_text = "Copy is marked as LOST";
					$circ = $session->request(
						"open-ils.storage.direct.action.circulation.search_where",
						{ target_copy => $copy->id, xact_finish => undef } )->gather(1);
				}

				$apputils->commit_db_session($session);

				return { 
					status => $status, 
					route_to => $user->home_ou, 
					text => $status_text, 
					record => $record, 
					circ	=> $circ,
					copy => $copy  };

			} else {

				$apputils->rollback_db_session($session);


				return { 
					copy => $copy, record => $record, 
					status => 3, route_to => $transit->dest, 
					text => "Transit needs to be routed" };

			}

		}


	} else { 

		$apputils->rollback_db_session($session);
		return { status => 12, route_to => $copy->circ_lib, text => "No transit found" };
	} 

}



__PACKAGE__->register_method(
	method	=> "checkin",
	api_name	=> "open-ils.circ.checkin.barcode",
	notes		=> <<"	NOTES");
	Checks in based on barcode
	Returns record, status, text, circ, copy, route_to 
	'status' values:
		0 = OK
		1 = 'copy required to fulfil a hold'
		2 = "copy is marked as lost"
		3 = "transit copy"
		4 = "transit for hold complete, put on holds shelf"
	NOTES

sub checkin {
	my( $self, $client, $user_session, $barcode, $isrenewal, $backdate ) = @_;

	my $err;
	my $copy;
	my $circ;
	my $iamlost;

	my $status = "0";
	my $status_text = "OK";
	my $route_to = "";

	my $transaction;
	my $user = $apputils->check_user_session($user_session);

	if($apputils->check_user_perms($user->id, $user->home_ou, "COPY_CHECKIN")) {
		return OpenILS::Perm->new("COPY_CHECKIN");
	}

	my $session = $apputils->start_db_session();
	my $transit_return;

	my $orig_copy_status;


	try {
			
		warn "retrieving copy for checkin\n";

			
		my $copy_req = $session->request(
			"open-ils.storage.direct.asset.copy.search.barcode.atomic", 
			$barcode );
		$copy = $copy_req->gather(1)->[0];
		if(!$copy) {
			$client->respond_complete(OpenILS::EX->new("UNKNOWN_BARCODE")->ex);
		}


		if($copy->status eq "3") { #if copy is lost
			$iamlost = 1;
		}

		if($copy->status eq "6") { #copy is in transit, deal with it
			my $method = $self->method_lookup("open-ils.circ.transit.receive");
			($transit_return) = $method->run( $user_session, $copy->id );

		} else {


			if(!$shelving_locations) {
				my $sh_req = $session->request(
					"open-ils.storage.direct.asset.copy_location.retrieve.all.atomic");
				$shelving_locations = $sh_req->gather(1);
				$shelving_locations = 
					{ map { (''.$_->id => $_->name) } @$shelving_locations };
			}
	
			
			$orig_copy_status = $copy->status;
			$copy->status(0);
		
			# find circ's where the transaction is still open for the
			# given copy.  should only be one.
			warn "Retrieving circ for checkin\n";
			my $circ_req = $session->request(
				"open-ils.storage.direct.action.circulation.search.atomic",
				{ target_copy => $copy->id, xact_finish => undef } );
		
			$circ = $circ_req->gather(1)->[0];
	
		
			if(!$circ) {
				$err = "No circulation exists for the given barcode";
	
			} else {
	
				$transaction = $session->request(
					"open-ils.storage.direct.money.billable_transaction_summary.retrieve", $circ->id)->gather(1);
		
				warn "Checking in circ ". $circ->id . "\n";
			
				$circ->stop_fines("CHECKIN");
				$circ->stop_fines("RENEW") if($isrenewal);
				$circ->xact_finish("now") if($transaction->balance_owed <= 0 );

				if($backdate) { 
					$circ->xact_finish($backdate); 

					# void any bills the resulted after the backdate time
					my $bills = $session->request(
						"open-ils.storage.direct.money.billing.search_where.atomic",
						billing_ts => { ">=" => $backdate })->gather(1);

					if($bills) {
						for my $bill (@$bills) {

							$bill->voided('t');
							my $s = $session->request(
								"open-ils.storage.direct.money.billing.update", $bill)->gather(1);

							if(!$s) { 
								throw OpenSRF::EX::ERROR 
									("Error voiding bill on checkin with backdate : $backdate, circ id: " . $circ->id);
							}
						}
					}
				}
			
				my $cp_up = $session->request(
					"open-ils.storage.direct.asset.copy.update", $copy );
				$cp_up->gather(1);
			
				my $ci_up = $session->request(
					"open-ils.storage.direct.action.circulation.update", $circ );


				$ci_up->gather(1);
			
				warn "Checkin succeeded\n";
			}
		}
		
	} catch Error with {
		my $e = shift;
		$err = "Error checking in: $e";
	};
	
	if($transit_return) { return $transit_return; }

	if($err) {

		return { record => undef, status => -1, text => $err };

	} else {


		# see if this copy can fulfill a hold
		my $hold = OpenILS::Application::Circ::Holds::_find_local_hold_for_copy( $session, $copy, $user );

		$route_to = $shelving_locations->{$copy->location};

		if($hold) { 
			warn "We found a hold that can be fulfilled by copy " . $copy->id . "\n";
			$status = "1";
			$status_text = "Copy needed to fulfill hold";
			$route_to = $hold->pickup_lib;
		}

		if($iamlost) {
			$status = "2";
			$status_text = "Copy is marked as LOST";
		}

		if(!$hold and $copy->circ_lib ne $user->home_ou) {

			warn "Checked in copy needs to be transited " . $copy->id . "\n";

			my $transit = Fieldmapper::action::transit_copy->new;
			$transit->source($user->home_ou);
			$transit->dest($copy->circ_lib);
			$transit->target_copy($copy->id);
			$transit->source_send_time("now");
			$transit->copy_status($orig_copy_status);

			my $s = $session->request(
				"open-ils.storage.direct.action.transit_copy.create", $transit )->gather(1);

			if(!$s){ throw OpenSRF::EX::ERROR 
				("Unable to create new transit for copy " . $copy->id ); }

			warn "Putting copy into in transit state \n";
			$copy->status(6); 
			$copy->editor($user->id); 
			$copy->edit_date("now"); 

			$s = $session->request(
				"open-ils.storage.direct.asset.copy.update", $copy )->gather(1);
			if(!$s) {throw OpenSRF::EX::ERROR ("Error updating copy ".$copy->id);} # blah..

			$status = 3;
			$status_text = "Copy needs to be routed to a different location";
			$route_to = $copy->circ_lib;
		}


	
		$apputils->commit_db_session($session);

		my $record = $apputils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy",
			$copy->id() );

		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch( $record->marc() );
		my $mods = $u->finish_mods_batch();

		return { 
			record	=> $mods, 
			status	=> $status,
			text		=> $status_text,
			circ		=> $circ,
			copy		=> $copy,
			route_to => $route_to,
		};
	}

	return 1;

}





# ------------------------------------------------------------------------------
# RENEWALS
# ------------------------------------------------------------------------------


__PACKAGE__->register_method(
	method	=> "renew",
	api_name	=> "open-ils.circ.renew",
	notes		=> <<"	NOTES");
	open-ils.circ.renew(login_session, circ_object);
	Renews the provided circulation.  login_session is the requestor of the
	renewal and if the logged in user is not the same as circ->usr, then
	the logged in user must have RENEW_CIRC permissions.
	NOTES

sub renew {
	my($self, $client, $login_session, $circ) = @_;

	throw OpenSRF::EX::InvalidArg 
		("open-ils.circ.renew no circ") unless defined($circ);

	my $user = $apputils->check_user_session($login_session);

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $copy = _grab_copy_by_id($session, $circ->target_copy);

	my $r = $session->request(
		"open-ils.storage.direct.action.hold_copy_map.search.target_copy.atomic",
		$copy->id )->gather(1);

	my @holdids = map { $_->hold  } @$r;

	if(@$r != 0) { 

		my $holds = $session->request(
			"open-ils.storage.direct.action.hold_request.search_where", 
				{ id => \@holdids, current_copy => undef } )->gather(1);

		if( $holds and $user->id ne $circ->usr ) {
			if($apputils->check_user_perms($user->id, $user->home_ou, "RENEW_HOLD_OVERRIDE")) {
				return OpenILS::Perm->new("RENEW_HOLD_OVERRIDE");
			}
		}

		return OpenILS::EX->new("COPY_NEEDED_FOR_HOLD")->ex; 
	}


	if(!ref($circ)) {
		$circ = $session->request(
			"open-ils.storage.direct.action.circulation.retrieve", $circ )->gather(1);
	}

	my $iid = $circ->id;
	warn "Attempting to renew circ " . $iid . "\n";

	if($user->id ne $circ->usr) {
		if($apputils->check_user_perms($user->id, $user->home_ou, "RENEW_CIRC")) {
			return OpenILS::Perm->new("RENEW_CIRC");
		}
	}

	if($circ->renewal_remaining <= 0) {
		return OpenILS::EX->new("MAX_RENEWALS_REACHED")->ex; }



	# XXX XXX See if the copy this circ points to is needed to fulfill a hold!
	# XXX check overdue..?

	my $checkin = $self->method_lookup("open-ils.circ.checkin.barcode");
	my ($status) = $checkin->run($login_session, $copy->barcode, 1);
	return $status if ($status->{status} ne "0"); 
	warn "Renewal checkin completed for $iid\n";

	my $permit_checkout = $self->method_lookup("open-ils.circ.permit_checkout");
	($status) = $permit_checkout->run($login_session, $copy->barcode, $circ->usr, "renew");
	return $status if($status->{status} ne "0");
	warn "Renewal permit checkout completed for $iid\n";

	my $checkout = $self->method_lookup("open-ils.circ.checkout.barcode");
	($status) = $checkout->run($login_session, $copy->barcode, $circ->usr, 1, $circ->renewal_remaining);
	warn "Renewal checkout completed for $iid\n";
	return $status;

}



1;
