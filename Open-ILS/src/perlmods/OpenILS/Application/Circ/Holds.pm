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


package OpenILS::Application::Circ::Holds;
use base qw/OpenILS::Application/;
use strict; use warnings;
use OpenILS::Application::AppUtils;
use DateTime;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::Perm;
use OpenILS::Event;
use OpenSRF::Utils;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::PermitHold;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Const qw/:const/;
use OpenILS::Application::Circ::Transit;
use OpenILS::Application::Actor::Friends;

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;




__PACKAGE__->register_method(
	method	=> "create_hold",
	api_name	=> "open-ils.circ.holds.create",
	notes		=> <<NOTE);
Create a new hold for an item.  From a permissions perspective, 
the login session is used as the 'requestor' of the hold.  
The hold recipient is determined by the 'usr' setting within
the hold object.

First we verify the requestion has holds request permissions.
Then we verify that the recipient is allowed to make the given hold.
If not, we see if the requestor has "override" capabilities.  If not,
a permission exception is returned.  If permissions allow, we cycle
through the set of holds objects and create.

If the recipient does not have permission to place multiple holds
on a single title and said operation is attempted, a permission
exception is returned
NOTE


__PACKAGE__->register_method(
	method	=> "create_hold",
	api_name	=> "open-ils.circ.holds.create.override",
	signature	=> q/
		If the recipient is not allowed to receive the requested hold,
		call this method to attempt the override
		@see open-ils.circ.holds.create
	/
);

sub create_hold {
	my( $self, $conn, $auth, @holds ) = @_;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->event unless $e->checkauth;

	my $override = 1 if $self->api_name =~ /override/;

	my $holds = (ref($holds[0] eq 'ARRAY')) ? $holds[0] : [@holds];

#	my @copyholds;

	for my $hold (@$holds) {

		next unless $hold;
		my @events;

		my $requestor = $e->requestor;
		my $recipient = $requestor;


		if( $requestor->id ne $hold->usr ) {
			# Make sure the requestor is allowed to place holds for 
			# the recipient if they are not the same people
			$recipient = $e->retrieve_actor_user($hold->usr) or return $e->event;
			$e->allowed('REQUEST_HOLDS', $recipient->home_ou) or return $e->event;
		}

		# Now make sure the recipient is allowed to receive the specified hold
		my $pevt;
		my $porg		= $recipient->home_ou;
		my $rid		= $e->requestor->id;
		my $t			= $hold->hold_type;

		# See if a duplicate hold already exists
		my $sargs = {
			usr			=> $recipient->id, 
			hold_type	=> $t, 
			fulfillment_time => undef, 
			target		=> $hold->target,
			cancel_time	=> undef,
		};

		$sargs->{holdable_formats} = $hold->holdable_formats if $t eq 'M';
			
		my $existing = $e->search_action_hold_request($sargs); 
		push( @events, OpenILS::Event->new('HOLD_EXISTS')) if @$existing;

		if( $t eq OILS_HOLD_TYPE_METARECORD ) 
			{ $pevt = $e->event unless $e->allowed('MR_HOLDS', $porg); }

		if( $t eq OILS_HOLD_TYPE_TITLE ) 
			{ $pevt = $e->event unless $e->allowed('TITLE_HOLDS', $porg);  }

		if( $t eq OILS_HOLD_TYPE_VOLUME ) 
			{ $pevt = $e->event unless $e->allowed('VOLUME_HOLDS', $porg); }

		if( $t eq OILS_HOLD_TYPE_COPY ) 
			{ $pevt = $e->event unless $e->allowed('COPY_HOLDS', $porg); }

		return $pevt if $pevt;

		if( @events ) {
			if( $override ) {
				for my $evt (@events) {
					next unless $evt;
					my $name = $evt->{textcode};
					return $e->event unless $e->allowed("$name.override", $porg);
				}
			} else {
				return \@events;
			}
		}

        # set the configured expire time
        unless($hold->expire_time) {
            my $interval = $U->ou_ancestor_setting_value($recipient->home_ou, OILS_SETTING_HOLD_EXPIRE);
            if($interval) {
                my $date = DateTime->now->add(seconds => OpenSRF::Utils::interval_to_seconds($interval));
                $hold->expire_time($U->epoch2ISO8601($date->epoch));
            }
        }

		$hold->requestor($e->requestor->id); 
		$hold->request_lib($e->requestor->ws_ou);
		$hold->selection_ou($hold->pickup_lib) unless $hold->selection_ou;
		$hold = $e->create_action_hold_request($hold) or return $e->event;
	}

	$e->commit;

	$conn->respond_complete(1);

    for(@holds) {
        next if $U->is_true($_->frozen);
	    $U->storagereq(
		    'open-ils.storage.action.hold_request.copy_targeter', 
		    undef, $_->id );
    }

	return undef;
}

sub __create_hold {
	my( $self, $client, $login_session, @holds) = @_;

	if(!@holds){return 0;}
	my( $user, $evt ) = $apputils->checkses($login_session);
	return $evt if $evt;

	my $holds;
	if(ref($holds[0]) eq 'ARRAY') {
		$holds = $holds[0];
	} else { $holds = [ @holds ]; }

	$logger->debug("Iterating over holds requests...");

	for my $hold (@$holds) {

		if(!$hold){next};
		my $type = $hold->hold_type;

		$logger->activity("User " . $user->id . 
			" creating new hold of type $type for user " . $hold->usr);

		my $recipient;
		if($user->id ne $hold->usr) {
			( $recipient, $evt ) = $apputils->fetch_user($hold->usr);
			return $evt if $evt;

		} else {
			$recipient = $user;
		}


		my $perm = undef;

		# am I allowed to place holds for this user?
		if($hold->requestor ne $hold->usr) {
			$perm = _check_request_holds_perm($user->id, $user->home_ou);
			if($perm) { return $perm; }
		}

		# is this user allowed to have holds of this type?
		$perm = _check_holds_perm($type, $hold->requestor, $recipient->home_ou);
        return $perm if $perm;

		#enforce the fact that the login is the one requesting the hold
		$hold->requestor($user->id); 
		$hold->selection_ou($recipient->home_ou) unless $hold->selection_ou;

		my $resp = $apputils->simplereq(
			'open-ils.storage',
			'open-ils.storage.direct.action.hold_request.create', $hold );

		if(!$resp) { 
			return OpenSRF::EX::ERROR ("Error creating hold"); 
		}
	}

	return 1;
}

# makes sure that a user has permission to place the type of requested hold
# returns the Perm exception if not allowed, returns undef if all is well
sub _check_holds_perm {
	my($type, $user_id, $org_id) = @_;

	my $evt;
	if($type eq "M") {
		if($evt = $apputils->check_perms(
			$user_id, $org_id, "MR_HOLDS")) {
			return $evt;
		} 

	} elsif ($type eq "T") {
		if($evt = $apputils->check_perms(
			$user_id, $org_id, "TITLE_HOLDS")) {
			return $evt;
		}

	} elsif($type eq "V") {
		if($evt = $apputils->check_perms(
			$user_id, $org_id, "VOLUME_HOLDS")) {
			return $evt;
		}

	} elsif($type eq "C") {
		if($evt = $apputils->check_perms(
			$user_id, $org_id, "COPY_HOLDS")) {
			return $evt;
		}
	}

	return undef;
}

# tests if the given user is allowed to place holds on another's behalf
sub _check_request_holds_perm {
	my $user_id = shift;
	my $org_id = shift;
	if(my $evt = $apputils->check_perms(
		$user_id, $org_id, "REQUEST_HOLDS")) {
		return $evt;
	}
}

__PACKAGE__->register_method(
	method	=> "retrieve_holds_by_id",
	api_name	=> "open-ils.circ.holds.retrieve_by_id",
	notes		=> <<NOTE);
Retrieve the hold, with hold transits attached, for the specified id The login session is the requestor and if the requestor is
different from the user, then the requestor must have VIEW_HOLD permissions.
NOTE


sub retrieve_holds_by_id {
	my($self, $client, $auth, $hold_id) = @_;
	my $e = new_editor(authtoken=>$auth);
	$e->checkauth or return $e->event;
	$e->allowed('VIEW_HOLD') or return $e->event;

	my $holds = $e->search_action_hold_request(
		[
			{ id =>  $hold_id , fulfillment_time => undef }, 
			{ order_by => { ahr => "request_time" } }
		]
	);

	flesh_hold_transits($holds);
	flesh_hold_notices($holds, $e);
	return $holds;
}


__PACKAGE__->register_method(
	method	=> "retrieve_holds",
	api_name	=> "open-ils.circ.holds.retrieve",
	notes		=> <<NOTE);
Retrieves all the holds, with hold transits attached, for the specified
user id.  The login session is the requestor and if the requestor is
different from the user, then the requestor must have VIEW_HOLD permissions.
NOTE

__PACKAGE__->register_method(
	method	=> "retrieve_holds",
    authoritative => 1,
	api_name	=> "open-ils.circ.holds.id_list.retrieve",
	notes		=> <<NOTE);
Retrieves all the hold ids for the specified
user id.  The login session is the requestor and if the requestor is
different from the user, then the requestor must have VIEW_HOLD permissions.
NOTE

sub retrieve_holds {
	my($self, $client, $auth, $user_id, $options) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $user_id = $e->requestor->id unless defined $user_id;
    $options ||= {};

    unless($user_id == $e->requestor->id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->event;
        unless($e->allowed('VIEW_HOLD', $user->home_ou)) {
            my $allowed = OpenILS::Application::Actor::Friends->friend_perm_allowed(
                $e, $user_id, $e->requestor->id, 'hold.view');
            return $e->event unless $allowed;
        }
    }

    my $holds = $e->search_action_hold_request([
		{   usr =>  $user_id , 
			fulfillment_time => undef,
			cancel_time => undef,
		}, 
		{order_by => {ahr => "request_time"}}
	]);

    if($$options{canceled}) {
        my $count = $$options{cancel_count} || 
            $U->ou_ancestor_setting_value($e->requestor->ws_ou, 
                'circ.canceled_hold_display_count', $e) || 5;

        my $canceled = $e->search_action_hold_request([
		    {   usr =>  $user_id , 
			    fulfillment_time => undef,
			    cancel_time => {'!=' => undef},
		    }, 
		    {order_by => {ahr => "cancel_time desc"}, limit => $count}
	    ]);
        push(@$holds, @$canceled);
    }
	
	if( ! $self->api_name =~ /id_list/ ) {
		for my $hold ( @$holds ) {
			$hold->transit(
                $e->search_action_hold_transit_copy([
					{hold => $hold->id},
					{order_by => {ahtc => 'id desc'}, limit => 1}])->[0]
			);
		}
	}

	if( $self->api_name =~ /id_list/ ) {
		return [ map { $_->id } @$holds ];
	} else {
		return $holds;
	}
}


__PACKAGE__->register_method(
   method => 'user_hold_count',
   api_name => 'open-ils.circ.hold.user.count');

sub user_hold_count {
   my( $self, $conn, $auth, $userid ) = @_;
   my $e = new_editor(authtoken=>$auth);
   return $e->event unless $e->checkauth;
   my $patron = $e->retrieve_actor_user($userid)
      or return $e->event;
   return $e->event unless $e->allowed('VIEW_HOLD', $patron->home_ou);
   return __user_hold_count($self, $e, $userid);
}

sub __user_hold_count {
   my( $self, $e, $userid ) = @_;
   my $holds = $e->search_action_hold_request(
      {  usr =>  $userid , 
         fulfillment_time => undef,
         cancel_time => undef,
      }, 
      {idlist => 1}
   );

   return scalar(@$holds);
}


__PACKAGE__->register_method(
	method	=> "retrieve_holds_by_pickup_lib",
	api_name	=> "open-ils.circ.holds.retrieve_by_pickup_lib",
	notes		=> <<NOTE);
Retrieves all the holds, with hold transits attached, for the specified
pickup_ou id. 
NOTE

__PACKAGE__->register_method(
	method	=> "retrieve_holds_by_pickup_lib",
	api_name	=> "open-ils.circ.holds.id_list.retrieve_by_pickup_lib",
	notes		=> <<NOTE);
Retrieves all the hold ids for the specified
pickup_ou id. 
NOTE

sub retrieve_holds_by_pickup_lib {
	my($self, $client, $login_session, $ou_id) = @_;

	#FIXME -- put an appropriate permission check here
	#my( $user, $target, $evt ) = $apputils->checkses_requestor(
	#	$login_session, $user_id, 'VIEW_HOLD' );
	#return $evt if $evt;

	my $holds = $apputils->simplereq(
		'open-ils.cstore',
		"open-ils.cstore.direct.action.hold_request.search.atomic",
		{ 
			pickup_lib =>  $ou_id , 
			fulfillment_time => undef,
			cancel_time => undef
		}, 
		{ order_by => { ahr => "request_time" } });


	if( ! $self->api_name =~ /id_list/ ) {
		flesh_hold_transits($holds);
	}

	if( $self->api_name =~ /id_list/ ) {
		return [ map { $_->id } @$holds ];
	} else {
		return $holds;
	}
}


__PACKAGE__->register_method(
	method	=> "uncancel_hold",
	api_name	=> "open-ils.circ.hold.uncancel"
);

sub uncancel_hold {
	my($self, $client, $auth, $hold_id) = @_;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->event unless $e->checkauth;

	my $hold = $e->retrieve_action_hold_request($hold_id)
		or return $e->die_event;
    return $e->die_event unless $e->allowed('CANCEL_HOLDS', $hold->request_lib);

    return 0 if $hold->fulfillment_time;
    return 1 unless $hold->cancel_time;

    # if configured to reset the request time, also reset the expire time
    if($U->ou_ancestor_setting_value(
        $hold->request_lib, 'circ.hold_reset_request_time_on_uncancel', $e)) {

        $hold->request_time('now');
        my $interval = $U->ou_ancestor_setting_value($hold->request_lib, OILS_SETTING_HOLD_EXPIRE);
        if($interval) {
            my $date = DateTime->now->add(seconds => OpenSRF::Utils::interval_to_seconds($interval));
            $hold->expire_time($U->epoch2ISO8601($date->epoch));
        }
    }

    $hold->clear_cancel_time;
    $e->update_action_hold_request($hold) or return $e->die_event;
    $e->commit;

    $U->storagereq('open-ils.storage.action.hold_request.copy_targeter', undef, $hold_id);

    return 1;
}


__PACKAGE__->register_method(
	method	=> "cancel_hold",
	api_name	=> "open-ils.circ.hold.cancel",
	notes		=> <<"	NOTE");
	Cancels the specified hold.  The login session
	is the requestor and if the requestor is different from the usr field
	on the hold, the requestor must have CANCEL_HOLDS permissions.
	the hold may be either the hold object or the hold id
	NOTE

sub cancel_hold {
	my($self, $client, $auth, $holdid, $cause, $note) = @_;

	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->event unless $e->checkauth;

	my $hold = $e->retrieve_action_hold_request($holdid)
		or return $e->event;

	if( $e->requestor->id ne $hold->usr ) {
		return $e->event unless $e->allowed('CANCEL_HOLDS');
	}

	return 1 if $hold->cancel_time;

	# If the hold is captured, reset the copy status
	if( $hold->capture_time and $hold->current_copy ) {

		my $copy = $e->retrieve_asset_copy($hold->current_copy)
			or return $e->event;

		if( $copy->status == OILS_COPY_STATUS_ON_HOLDS_SHELF ) {
         $logger->info("canceling hold $holdid whose item is on the holds shelf");
#			$logger->info("setting copy to status 'reshelving' on hold cancel");
#			$copy->status(OILS_COPY_STATUS_RESHELVING);
#			$copy->editor($e->requestor->id);
#			$copy->edit_date('now');
#			$e->update_asset_copy($copy) or return $e->event;

		} elsif( $copy->status == OILS_COPY_STATUS_IN_TRANSIT ) {

			my $hid = $hold->id;
			$logger->warn("! canceling hold [$hid] that is in transit");
			my $transid = $e->search_action_hold_transit_copy({hold=>$hold->id},{idlist=>1})->[0];

			if( $transid ) {
				my $trans = $e->retrieve_action_transit_copy($transid);
				# Leave the transit alive, but  set the copy status to 
				# reshelving so it will be properly reshelved when it gets back home
				if( $trans ) {
					$trans->copy_status( OILS_COPY_STATUS_RESHELVING );
					$e->update_action_transit_copy($trans) or return $e->die_event;
				}
			}
		}
	}

	$hold->cancel_time('now');
    $hold->cancel_cause($cause);
    $hold->cancel_note($note);
	$e->update_action_hold_request($hold)
		or return $e->event;

	delete_hold_copy_maps($self, $e, $hold->id);

	$e->commit;
	return 1;
}

sub delete_hold_copy_maps {
	my $class = shift;
	my $editor = shift;
	my $holdid = shift;

	my $maps = $editor->search_action_hold_copy_map({hold=>$holdid});
	for(@$maps) {
		$editor->delete_action_hold_copy_map($_) 
			or return $editor->event;
	}
	return undef;
}


__PACKAGE__->register_method(
	method	=> "update_hold",
	api_name	=> "open-ils.circ.hold.update",
	notes		=> <<"	NOTE");
	Updates the specified hold.  The login session
	is the requestor and if the requestor is different from the usr field
	on the hold, the requestor must have UPDATE_HOLDS permissions.
	NOTE

sub update_hold {
	my($self, $client, $auth, $hold) = @_;

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    my $orig_hold = $e->retrieve_action_hold_request($hold->id)
        or return $e->die_event;

    # don't allow the user to be changed
    return OpenILS::Event->new('BAD_PARAMS') if $hold->usr != $orig_hold->usr;

    if($hold->usr ne $e->requestor->id) {
        # if the hold is for a different user, make sure the 
        # requestor has the appropriate permissions
        my $usr = $e->retrieve_actor_user($hold->usr)
            or return $e->die_event;
        return $e->die_event unless $e->allowed('UPDATE_HOLD', $usr->home_ou);
    }

    # --------------------------------------------------------------
    # if the hold is on the holds shelf and the pickup lib changes, 
    # we need to create a new transit
    # --------------------------------------------------------------
    if( ($orig_hold->pickup_lib ne $hold->pickup_lib) and (_hold_status($e, $hold) == 4)) {
        return $e->die_event unless $e->allowed('UPDATE_PICKUP_LIB_FROM_HOLDS_SHELF', $orig_hold->pickup_lib);
        return $e->die_event unless $e->allowed('UPDATE_PICKUP_LIB_FROM_HOLDS_SHELF', $hold->pickup_lib);
        my $evt = transit_hold($e, $orig_hold, $hold, 
            $e->retrieve_asset_copy($hold->current_copy));
        return $evt if $evt;
    }

    update_hold_if_frozen($self, $e, $hold, $orig_hold);
    $e->update_action_hold_request($hold) or return $e->die_event;
    $e->commit;
    return $hold->id;
}

sub transit_hold {
    my($e, $orig_hold, $hold, $copy) = @_;
    my $src = $orig_hold->pickup_lib;
    my $dest = $hold->pickup_lib;

    $logger->info("putting hold into transit on pickup_lib update");

    my $transit = Fieldmapper::action::transit_copy->new;
    $transit->source($src);
    $transit->dest($dest);
    $transit->target_copy($copy->id);
    $transit->source_send_time('now');
    $transit->copy_status(OILS_COPY_STATUS_ON_HOLDS_SHELF);

    $copy->status(OILS_COPY_STATUS_IN_TRANSIT);
    $copy->editor($e->requestor->id);
    $copy->edit_date('now');

    $e->create_action_transit_copy($transit) or return $e->die_event;
    $e->update_asset_copy($copy) or return $e->die_event;
    return undef;
}

# if the hold is frozen, this method ensures that the hold is not "targeted", 
# that is, it clears the current_copy and prev_check_time to essentiallly 
# reset the hold.  If it is being activated, it runs the targeter in the background
sub update_hold_if_frozen {
    my($self, $e, $hold, $orig_hold) = @_;
    return if $hold->capture_time;

    if($U->is_true($hold->frozen)) {
        $logger->info("clearing current_copy and check_time for frozen hold ".$hold->id);
        $hold->clear_current_copy;
        $hold->clear_prev_check_time;

    } else {
        if($U->is_true($orig_hold->frozen)) {
            $logger->info("Running targeter on activated hold ".$hold->id);
	        $U->storagereq( 'open-ils.storage.action.hold_request.copy_targeter', undef, $hold->id );
        }
    }
}


__PACKAGE__->register_method(
	method	=> "retrieve_hold_status",
	api_name	=> "open-ils.circ.hold.status.retrieve",
	notes		=> <<"	NOTE");
	Calculates the current status of the hold.
	the requestor must have VIEW_HOLD permissions if the hold is for a user
	other than the requestor.
	Returns -1  on error (for now)
	Returns 1 for 'waiting for copy to become available'
	Returns 2 for 'waiting for copy capture'
	Returns 3 for 'in transit'
	Returns 4 for 'arrived'
	NOTE

sub retrieve_hold_status {
	my($self, $client, $auth, $hold_id) = @_;

	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;
	my $hold = $e->retrieve_action_hold_request($hold_id)
		or return $e->event;

	if( $e->requestor->id != $hold->usr ) {
		return $e->event unless $e->allowed('VIEW_HOLD');
	}

	return _hold_status($e, $hold);

}

sub _hold_status {
	my($e, $hold) = @_;
	return 1 unless $hold->current_copy;
	return 2 unless $hold->capture_time;

	my $copy = $hold->current_copy;
	unless( ref $copy ) {
		$copy = $e->retrieve_asset_copy($hold->current_copy)
			or return $e->event;
	}

	return 3 if $copy->status == OILS_COPY_STATUS_IN_TRANSIT;
	return 4 if $copy->status == OILS_COPY_STATUS_ON_HOLDS_SHELF;

	return -1;
}



__PACKAGE__->register_method(
	method	=> "retrieve_hold_queue_stats",
	api_name	=> "open-ils.circ.hold.queue_stats.retrieve",
    signature => {
        desc => q/
            Returns object with total_holds count, queue_position, potential_copies count, and status code
        /
    }
);

sub retrieve_hold_queue_stats {
    my($self, $conn, $auth, $hold_id) = @_;
	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;
	my $hold = $e->retrieve_action_hold_request($hold_id) or return $e->event;
	if($e->requestor->id != $hold->usr) {
		return $e->event unless $e->allowed('VIEW_HOLD');
	}
    return retrieve_hold_queue_status_impl($e, $hold);
}

sub retrieve_hold_queue_status_impl {
    my $e = shift;
    my $hold = shift;

    my $hold_ids = $e->search_action_hold_request(
        [
            {   target => $hold->target, 
                hold_type => $hold->hold_type,
                cancel_time => undef,
                capture_time => undef
            },
            {order_by => {ahr => 'request_time asc'}}
        ], 
        {idlist => 1} 
    );

    my $qpos = 0;
    for my $hid (@$hold_ids) {
        $qpos++;
        last if $hid == $hold->id;
    }

    my $potentials = $e->search_action_hold_copy_map({hold => $hold->id}, {idlist => 1});
    my $num_potentials = scalar(@$potentials);

    my $user_org = $e->json_query({select => {au => 'home_ou'}, from => 'au', where => {id => $hold->usr}})->[0]->{home_ou};
    my $default_hold_interval = $U->ou_ancestor_setting_value($user_org, OILS_SETTING_HOLD_ESIMATE_WAIT_INTERVAL);
    my $estimated_wait = $qpos * ($default_hold_interval / $num_potentials) if $default_hold_interval;

    return {
        total_holds => scalar(@$hold_ids),
        queue_position => $qpos,
        potential_copies => $num_potentials,
        status => _hold_status($e, $hold),
        estimated_wait => int($estimated_wait)
    };
}


sub fetch_open_hold_by_current_copy {
	my $class = shift;
	my $copyid = shift;
	my $hold = $apputils->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.action.hold_request.search.atomic',
		{ current_copy =>  $copyid , cancel_time => undef, fulfillment_time => undef });
	return $hold->[0] if ref($hold);
	return undef;
}

sub fetch_related_holds {
	my $class = shift;
	my $copyid = shift;
	return $apputils->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.action.hold_request.search.atomic',
		{ current_copy =>  $copyid , cancel_time => undef, fulfillment_time => undef });
}


__PACKAGE__->register_method (
	method		=> "hold_pull_list",
	api_name		=> "open-ils.circ.hold_pull_list.retrieve",
	signature	=> q/
		Returns a list of holds that need to be "pulled"
		by a given location
	/
);

__PACKAGE__->register_method (
	method		=> "hold_pull_list",
	api_name		=> "open-ils.circ.hold_pull_list.id_list.retrieve",
	signature	=> q/
		Returns a list of hold ID's that need to be "pulled"
		by a given location
	/
);


sub hold_pull_list {
	my( $self, $conn, $authtoken, $limit, $offset ) = @_;
	my( $reqr, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;

	my $org = $reqr->ws_ou || $reqr->home_ou;
	# the perm locaiton shouldn't really matter here since holds
	# will exist all over and VIEW_HOLDS should be universal
	$evt = $U->check_perms($reqr->id, $org, 'VIEW_HOLD');
	return $evt if $evt;

	if( $self->api_name =~ /id_list/ ) {
		return $U->storagereq(
			'open-ils.storage.direct.action.hold_request.pull_list.id_list.current_copy_circ_lib.status_filtered.atomic',
			$org, $limit, $offset ); 
	} else {
		return $U->storagereq(
			'open-ils.storage.direct.action.hold_request.pull_list.search.current_copy_circ_lib.status_filtered.atomic',
			$org, $limit, $offset ); 
	}
}

__PACKAGE__->register_method (
	method		=> 'fetch_hold_notify',
	api_name		=> 'open-ils.circ.hold_notification.retrieve_by_hold',
	signature	=> q/ 
		Returns a list of hold notification objects based on hold id.
		@param authtoken The loggin session key
		@param holdid The id of the hold whose notifications we want to retrieve
		@return An array of hold notification objects, event on error.
	/
);

sub fetch_hold_notify {
	my( $self, $conn, $authtoken, $holdid ) = @_;
	my( $requestor, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;
	my ($hold, $patron);
	($hold, $evt) = $U->fetch_hold($holdid);
	return $evt if $evt;
	($patron, $evt) = $U->fetch_user($hold->usr);
	return $evt if $evt;

	$evt = $U->check_perms($requestor->id, $patron->home_ou, 'VIEW_HOLD_NOTIFICATION');
	return $evt if $evt;

	$logger->info("User ".$requestor->id." fetching hold notifications for hold $holdid");
	return $U->cstorereq(
		'open-ils.cstore.direct.action.hold_notification.search.atomic', {hold => $holdid} );
}


__PACKAGE__->register_method (
	method		=> 'create_hold_notify',
	api_name		=> 'open-ils.circ.hold_notification.create',
	signature	=> q/
		Creates a new hold notification object
		@param authtoken The login session key
		@param notification The hold notification object to create
		@return ID of the new object on success, Event on error
		/
);

sub create_hold_notify {
   my( $self, $conn, $auth, $note ) = @_;
   my $e = new_editor(authtoken=>$auth, xact=>1);
   return $e->die_event unless $e->checkauth;

   my $hold = $e->retrieve_action_hold_request($note->hold)
      or return $e->die_event;
   my $patron = $e->retrieve_actor_user($hold->usr) 
      or return $e->die_event;

   return $e->die_event unless 
      $e->allowed('CREATE_HOLD_NOTIFICATION', $patron->home_ou);

	$note->notify_staff($e->requestor->id);
   $e->create_action_hold_notification($note) or return $e->die_event;
   $e->commit;
   return $note->id;
}


__PACKAGE__->register_method(
	method	=> 'reset_hold',
	api_name	=> 'open-ils.circ.hold.reset',
	signature	=> q/
		Un-captures and un-targets a hold, essentially returning
		it to the state it was in directly after it was placed,
		then attempts to re-target the hold
		@param authtoken The login session key
		@param holdid The id of the hold
	/
);


sub reset_hold {
	my( $self, $conn, $auth, $holdid ) = @_;
	my $reqr;
	my ($hold, $evt) = $U->fetch_hold($holdid);
	return $evt if $evt;
	($reqr, $evt) = $U->checksesperm($auth, 'UPDATE_HOLD'); # XXX stronger permission
	return $evt if $evt;
	$evt = _reset_hold($self, $reqr, $hold);
	return $evt if $evt;
	return 1;
}

sub _reset_hold {
	my ($self, $reqr, $hold) = @_;

	my $e = new_editor(xact =>1, requestor => $reqr);

	$logger->info("reseting hold ".$hold->id);

	my $hid = $hold->id;

	if( $hold->capture_time and $hold->current_copy ) {

		my $copy = $e->retrieve_asset_copy($hold->current_copy)
			or return $e->event;

		if( $copy->status == OILS_COPY_STATUS_ON_HOLDS_SHELF ) {
			$logger->info("setting copy to status 'reshelving' on hold retarget");
			$copy->status(OILS_COPY_STATUS_RESHELVING);
			$copy->editor($e->requestor->id);
			$copy->edit_date('now');
			$e->update_asset_copy($copy) or return $e->event;

		} elsif( $copy->status == OILS_COPY_STATUS_IN_TRANSIT ) {

			# We don't want the copy to remain "in transit"
			$copy->status(OILS_COPY_STATUS_RESHELVING);
			$logger->warn("! reseting hold [$hid] that is in transit");
			my $transid = $e->search_action_hold_transit_copy({hold=>$hold->id},{idlist=>1})->[0];

			if( $transid ) {
				my $trans = $e->retrieve_action_transit_copy($transid);
				if( $trans ) {
					$logger->info("Aborting transit [$transid] on hold [$hid] reset...");
					my $evt = OpenILS::Application::Circ::Transit::__abort_transit($e, $trans, $copy, 1);
					$logger->info("Transit abort completed with result $evt");
					return $evt unless "$evt" eq 1;
				}
			}
		}
	}

	$hold->clear_capture_time;
	$hold->clear_current_copy;

	$e->update_action_hold_request($hold) or return $e->event;
	$e->commit;

	$U->storagereq(
		'open-ils.storage.action.hold_request.copy_targeter', undef, $hold->id );

	return undef;
}


__PACKAGE__->register_method(
	method => 'fetch_open_title_holds',
	api_name	=> 'open-ils.circ.open_holds.retrieve',
	signature	=> q/
		Returns a list ids of un-fulfilled holds for a given title id
		@param authtoken The login session key
		@param id the id of the item whose holds we want to retrieve
		@param type The hold type - M, T, V, C
	/
);

sub fetch_open_title_holds {
	my( $self, $conn, $auth, $id, $type, $org ) = @_;
	my $e = new_editor( authtoken => $auth );
	return $e->event unless $e->checkauth;

	$type ||= "T";
	$org ||= $e->requestor->ws_ou;

#	return $e->search_action_hold_request(
#		{ target => $id, hold_type => $type, fulfillment_time => undef }, {idlist=>1});

	# XXX make me return IDs in the future ^--
	my $holds = $e->search_action_hold_request(
		{ 
			target				=> $id, 
			cancel_time			=> undef, 
			hold_type			=> $type, 
			fulfillment_time	=> undef 
		}
	);

	flesh_hold_transits($holds);
	return $holds;
}


sub flesh_hold_transits {
	my $holds = shift;
	for my $hold ( @$holds ) {
		$hold->transit(
			$apputils->simplereq(
				'open-ils.cstore',
				"open-ils.cstore.direct.action.hold_transit_copy.search.atomic",
				{ hold => $hold->id },
				{ order_by => { ahtc => 'id desc' }, limit => 1 }
			)->[0]
		);
	}
}

sub flesh_hold_notices {
	my( $holds, $e ) = @_;
	$e ||= new_editor();

	for my $hold (@$holds) {
		my $notices = $e->search_action_hold_notification(
			[
				{ hold => $hold->id },
				{ order_by => { anh => 'notify_time desc' } },
			],
			{idlist=>1}
		);

		$hold->notify_count(scalar(@$notices));
		if( @$notices ) {
			my $n = $e->retrieve_action_hold_notification($$notices[0])
				or return $e->event;
			$hold->notify_time($n->notify_time);
		}
	}
}


__PACKAGE__->register_method(
	method => 'fetch_captured_holds',
	api_name	=> 'open-ils.circ.captured_holds.on_shelf.retrieve',
    stream => 1,
	signature	=> q/
		Returns a list of un-fulfilled holds for a given title id
		@param authtoken The login session key
		@param org The org id of the location in question
	/
);

__PACKAGE__->register_method(
	method => 'fetch_captured_holds',
	api_name	=> 'open-ils.circ.captured_holds.id_list.on_shelf.retrieve',
    stream => 1,
	signature	=> q/
		Returns a list ids of un-fulfilled holds for a given title id
		@param authtoken The login session key
		@param org The org id of the location in question
	/
);

sub fetch_captured_holds {
	my( $self, $conn, $auth, $org ) = @_;

	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_HOLD'); # XXX rely on editor perm

	$org ||= $e->requestor->ws_ou;

    my $hold_ids = $e->json_query(
        { 
            select => { ahr => ['id'] },
            from => {
                ahr => {
                    acp => {
                        field => 'id',
                        fkey => 'current_copy'
                    },
                }
            }, 
            where => {
                '+acp' => { status => OILS_COPY_STATUS_ON_HOLDS_SHELF },
                '+ahr' => {
                    capture_time		=> { "!=" => undef },
                    current_copy		=> { "!=" => undef },
                    fulfillment_time	=> undef,
                    pickup_lib			=> $org,
                    cancel_time			=> undef,
                }
            }
        },
    );

    for my $hold_id (@$hold_ids) {
        if($self->api_name =~ /id_list/) {
            $conn->respond($hold_id->{id});
            next;
        } else {
            $conn->respond(
                $e->retrieve_action_hold_request([
                    $hold_id->{id},
                    {
                        flesh => 1,
                        flesh_fields => {ahr => ['notifications', 'transit']},
                        order_by => {anh => 'notify_time desc'}
                    }
                ])
            );
        }
    }

    return undef;
}
__PACKAGE__->register_method(
	method	=> "check_title_hold",
	api_name	=> "open-ils.circ.title_hold.is_possible",
	notes		=> q/
		Determines if a hold were to be placed by a given user,
		whether or not said hold would have any potential copies
		to fulfill it.
		@param authtoken The login session key
		@param params A hash of named params including:
			patronid  - the id of the hold recipient
			titleid (brn) - the id of the title to be held
			depth	- the hold range depth (defaults to 0)
	/);

sub check_title_hold {
	my( $self, $client, $authtoken, $params ) = @_;

	my %params		= %$params;
	my $titleid		= $params{titleid} ||"";
	my $volid		= $params{volume_id};
	my $copyid		= $params{copy_id};
	my $mrid		= $params{mrid} ||"";
	my $depth		= $params{depth} || 0;
	my $pickup_lib	= $params{pickup_lib};
	my $hold_type	= $params{hold_type} || 'T';
    my $selection_ou = $params{selection_ou} || $pickup_lib;

	my $e = new_editor(authtoken=>$authtoken);
	return $e->event unless $e->checkauth;
	my $patron = $e->retrieve_actor_user($params{patronid})
		or return $e->event;

	if( $e->requestor->id ne $patron->id ) {
		return $e->event unless 
			$e->allowed('VIEW_HOLD_PERMIT', $patron->home_ou);
	}

	return OpenILS::Event->new('PATRON_BARRED') if $U->is_true($patron->barred);

	my $request_lib = $e->retrieve_actor_org_unit($e->requestor->ws_ou)
		or return $e->event;

    my $soft_boundary = $U->ou_ancestor_setting_value($selection_ou, OILS_SETTING_HOLD_SOFT_BOUNDARY);
    my $hard_boundary = $U->ou_ancestor_setting_value($selection_ou, OILS_SETTING_HOLD_HARD_BOUNDARY);

    if(defined $soft_boundary and $$params{depth} < $soft_boundary) {
        # work up the tree and as soon as we find a potential copy, use that depth
        # also, make sure we don't go past the hard boundary if it exists

        # our min boundary is the greater of user-specified boundary or hard boundary
        my $min_depth = (defined $hard_boundary and $hard_boundary > $$params{depth}) ?  
            $hard_boundary : $$params{depth};

        my $depth = $soft_boundary;
        while($depth >= $min_depth) {
            $logger->info("performing hold possibility check with soft boundary $depth");
            return {success => 1, depth => $depth}
                if do_possibility_checks($e, $patron, $request_lib, $depth, %params);
            $depth--;
        }
        return {success => 0};

    } elsif(defined $hard_boundary and $$params{depth} < $hard_boundary) {
        # there is no soft boundary, enforce the hard boundary if it exists
        $logger->info("performing hold possibility check with hard boundary $hard_boundary");
        if(do_possibility_checks($e, $patron, $request_lib, $hard_boundary, %params)) {
            return {success => 1, depth => $hard_boundary}
        } else {
            return {success => 0};
        }

    } else {
        # no boundaries defined, fall back to user specifed boundary or no boundary
        $logger->info("performing hold possibility check with no boundary");
        if(do_possibility_checks($e, $patron, $request_lib, $params{depth}, %params)) {
            return {success => 1, depth => $hard_boundary};
        } else {
            return {success => 0};
        }
    }
}

sub do_possibility_checks {
    my($e, $patron, $request_lib, $depth, %params) = @_;

	my $titleid		= $params{titleid} ||"";
	my $volid		= $params{volume_id};
	my $copyid		= $params{copy_id};
	my $mrid		= $params{mrid} ||"";
	my $pickup_lib	= $params{pickup_lib};
	my $hold_type	= $params{hold_type} || 'T';
    my $selection_ou = $params{selection_ou} || $pickup_lib;


	my $copy;
	my $volume;
	my $title;

	if( $hold_type eq OILS_HOLD_TYPE_COPY ) {

		$copy = $e->retrieve_asset_copy($copyid) or return $e->event;
		$volume = $e->retrieve_asset_call_number($copy->call_number)
			or return $e->event;
		$title = $e->retrieve_biblio_record_entry($volume->record)
			or return $e->event;
		return verify_copy_for_hold( 
			$patron, $e->requestor, $title, $copy, $pickup_lib, $request_lib );

	} elsif( $hold_type eq OILS_HOLD_TYPE_VOLUME ) {

		$volume = $e->retrieve_asset_call_number($volid)
			or return $e->event;
		$title = $e->retrieve_biblio_record_entry($volume->record)
			or return $e->event;

		return _check_volume_hold_is_possible(
			$volume, $title, $depth, $request_lib, $patron, $e->requestor, $pickup_lib, $selection_ou);

	} elsif( $hold_type eq OILS_HOLD_TYPE_TITLE ) {

		return _check_title_hold_is_possible(
			$titleid, $depth, $request_lib, $patron, $e->requestor, $pickup_lib, $selection_ou);

	} elsif( $hold_type eq OILS_HOLD_TYPE_METARECORD ) {

		my $maps = $e->search_metabib_source_map({metarecord=>$mrid});
		my @recs = map { $_->source } @$maps;
		for my $rec (@recs) {
			return 1 if (_check_title_hold_is_possible(
				$rec, $depth, $request_lib, $patron, $e->requestor, $pickup_lib, $selection_ou));
		}
		return 0;	
	}
}

my %prox_cache;

sub _check_metarecord_hold_is_possible {
	my( $mrid, $rangelib, $depth, $request_lib, $patron, $requestor, $pickup_lib ) = @_;
   
   my $e = new_editor();

    # this monster will grab the id and circ_lib of all of the "holdable" copies for the given metarecord
    my $copies = $e->json_query(
        { 
            select => { acp => ['id', 'circ_lib'] },
            from => {
                acp => {
                    acn => {
                        field => 'id',
                        fkey => 'call_number',
                        'join' => {
                            mmrsm => {
                                field => 'source',
                                fkey => 'record',
                               	filter => { metarecord => $mrid }
                            }
                        }
                    },
                    acpl => { field => 'id', filter => { holdable => 't'}, fkey => 'location' },
                    ccs => { field => 'id', filter => { holdable => 't'}, fkey => 'status' }
                }
            }, 
            where => {
                '+acp' => { circulate => 't', deleted => 'f', holdable => 't' }
            }
        }
    );

   return $e->event unless defined $copies;
   $logger->info("metarecord possible found ".scalar(@$copies)." potential copies");
   return 0 unless @$copies;

   # -----------------------------------------------------------------------
   # sort the copies into buckets based on their circ_lib proximity to 
   # the patron's home_ou.  
   # -----------------------------------------------------------------------

   my $home_org = $patron->home_ou;
   my $req_org = $request_lib->id;

    $prox_cache{$home_org} = 
        $e->search_actor_org_unit_proximity({from_org => $home_org})
        unless $prox_cache{$home_org};
    my $home_prox = $prox_cache{$home_org};

   my %buckets;
   my %hash = map { ($_->to_org => $_->prox) } @$home_prox;
   push( @{$buckets{ $hash{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

   my @keys = sort { $a <=> $b } keys %buckets;


   if( $home_org ne $req_org ) {
      # -----------------------------------------------------------------------
      # shove the copies close to the request_lib into the primary buckets 
      # directly before the farthest away copies.  That way, they are not 
      # given priority, but they are checked before the farthest copies.
      # -----------------------------------------------------------------------

        $prox_cache{$req_org} = 
            $e->search_actor_org_unit_proximity({from_org => $req_org})
            unless $prox_cache{$req_org};
        my $req_prox = $prox_cache{$req_org};

      my %buckets2;
      my %hash2 = map { ($_->to_org => $_->prox) } @$req_prox;
      push( @{$buckets2{ $hash2{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

      my $highest_key = $keys[@keys - 1];  # the farthest prox in the exising buckets
      my $new_key = $highest_key - 0.5; # right before the farthest prox
      my @keys2 = sort { $a <=> $b } keys %buckets2;
      for my $key (@keys2) {
         last if $key >= $highest_key;
         push( @{$buckets{$new_key}}, $_ ) for @{$buckets2{$key}};
      }
   }

   @keys = sort { $a <=> $b } keys %buckets;

   my %seen;
   for my $key (@keys) {
      my @cps = @{$buckets{$key}};

      $logger->info("looking at " . scalar(@{$buckets{$key}}). " copies in proximity bucket $key");

      for my $copyid (@cps) {

         next if $seen{$copyid};
         $seen{$copyid} = 1; # there could be dupes given the merged buckets
         my $copy = $e->retrieve_asset_copy($copyid) or return $e->event;
         $logger->debug("looking at bucket_key=$key, copy $copyid : circ_lib = " . $copy->circ_lib);

         my $vol = $e->retrieve_asset_call_number(
           [ $copy->call_number, { flesh => 1, flesh_fields => { acn => ['record'] } } ] );

         return 1 if verify_copy_for_hold( 
            $patron, $requestor, $vol->record, $copy, $pickup_lib, $request_lib );
   
      }
   }

   return 0;
}

sub create_ranged_org_filter {
    my($e, $selection_ou, $depth) = @_;

    # find the orgs from which this hold may be fulfilled, 
    # based on the selection_ou and depth

    my $top_org = $e->search_actor_org_unit([
        {parent_ou => undef}, 
        {flesh=>1, flesh_fields=>{aou=>['ou_type']}}])->[0];
    my %org_filter;

    return () if $depth == $top_org->ou_type->depth;

    my $org_list = $U->storagereq('open-ils.storage.actor.org_unit.descendants.atomic', $selection_ou, $depth);
    %org_filter = (circ_lib => []);
    push(@{$org_filter{circ_lib}}, $_->id) for @$org_list;

    $logger->info("hold org filter at depth $depth and selection_ou ".
        "$selection_ou created list of @{$org_filter{circ_lib}}");

    return %org_filter;
}


sub _check_title_hold_is_possible {
	my( $titleid, $depth, $request_lib, $patron, $requestor, $pickup_lib, $selection_ou ) = @_;
   
    my $e = new_editor();
    my %org_filter = create_ranged_org_filter($e, $selection_ou, $depth);

    # this monster will grab the id and circ_lib of all of the "holdable" copies for the given record
    my $copies = $e->json_query(
        { 
            select => { acp => ['id', 'circ_lib'] },
            from => {
                acp => {
                    acn => {
                        field => 'id',
                        fkey => 'call_number',
                        'join' => {
                            bre => {
                                field => 'id',
                                filter => { id => $titleid },
                                fkey => 'record'
                            }
                        }
                    },
                    acpl => { field => 'id', filter => { holdable => 't'}, fkey => 'location' },
                    ccs => { field => 'id', filter => { holdable => 't'}, fkey => 'status' }
                }
            }, 
            where => {
                '+acp' => { circulate => 't', deleted => 'f', holdable => 't', %org_filter }
            }
        }
    );

   return $e->event unless defined $copies;
   $logger->info("title possible found ".scalar(@$copies)." potential copies");
   return 0 unless @$copies;

   # -----------------------------------------------------------------------
   # sort the copies into buckets based on their circ_lib proximity to 
   # the patron's home_ou.  
   # -----------------------------------------------------------------------

   my $home_org = $patron->home_ou;
   my $req_org = $request_lib->id;

    $logger->info("prox cache $home_org " . $prox_cache{$home_org});

    $prox_cache{$home_org} = 
        $e->search_actor_org_unit_proximity({from_org => $home_org})
        unless $prox_cache{$home_org};
    my $home_prox = $prox_cache{$home_org};

   my %buckets;
   my %hash = map { ($_->to_org => $_->prox) } @$home_prox;
   push( @{$buckets{ $hash{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

   my @keys = sort { $a <=> $b } keys %buckets;


   if( $home_org ne $req_org ) {
      # -----------------------------------------------------------------------
      # shove the copies close to the request_lib into the primary buckets 
      # directly before the farthest away copies.  That way, they are not 
      # given priority, but they are checked before the farthest copies.
      # -----------------------------------------------------------------------
        $prox_cache{$req_org} = 
            $e->search_actor_org_unit_proximity({from_org => $req_org})
            unless $prox_cache{$req_org};
        my $req_prox = $prox_cache{$req_org};


      my %buckets2;
      my %hash2 = map { ($_->to_org => $_->prox) } @$req_prox;
      push( @{$buckets2{ $hash2{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

      my $highest_key = $keys[@keys - 1];  # the farthest prox in the exising buckets
      my $new_key = $highest_key - 0.5; # right before the farthest prox
      my @keys2 = sort { $a <=> $b } keys %buckets2;
      for my $key (@keys2) {
         last if $key >= $highest_key;
         push( @{$buckets{$new_key}}, $_ ) for @{$buckets2{$key}};
      }
   }

   @keys = sort { $a <=> $b } keys %buckets;

   my $title;
   my %seen;
   for my $key (@keys) {
      my @cps = @{$buckets{$key}};

      $logger->info("looking at " . scalar(@{$buckets{$key}}). " copies in proximity bucket $key");

      for my $copyid (@cps) {

         next if $seen{$copyid};
         $seen{$copyid} = 1; # there could be dupes given the merged buckets
         my $copy = $e->retrieve_asset_copy($copyid) or return $e->event;
         $logger->debug("looking at bucket_key=$key, copy $copyid : circ_lib = " . $copy->circ_lib);

         unless($title) { # grab the title if we don't already have it
            my $vol = $e->retrieve_asset_call_number(
               [ $copy->call_number, { flesh => 1, flesh_fields => { acn => ['record'] } } ] );
            $title = $vol->record;
         }
   
         return 1 if verify_copy_for_hold( 
            $patron, $requestor, $title, $copy, $pickup_lib, $request_lib );
   
      }
   }

   return 0;
}


sub _check_volume_hold_is_possible {
	my( $vol, $title, $depth, $request_lib, $patron, $requestor, $pickup_lib, $selection_ou ) = @_;
    my %org_filter = create_ranged_org_filter(new_editor(), $selection_ou, $depth);
	my $copies = new_editor->search_asset_copy({call_number => $vol->id, %org_filter});
	$logger->info("checking possibility of volume hold for volume ".$vol->id);
	for my $copy ( @$copies ) {
		return 1 if verify_copy_for_hold( 
			$patron, $requestor, $title, $copy, $pickup_lib, $request_lib );
	}
	return 0;
}



sub verify_copy_for_hold {
	my( $patron, $requestor, $title, $copy, $pickup_lib, $request_lib ) = @_;
	$logger->info("checking possibility of copy in hold request for copy ".$copy->id);
	return 1 if OpenILS::Utils::PermitHold::permit_copy_hold(
		{	patron				=> $patron, 
			requestor			=> $requestor, 
			copy				=> $copy,
			title				=> $title, 
			title_descriptor	=> $title->fixed_fields, # this is fleshed into the title object
			pickup_lib			=> $pickup_lib,
			request_lib			=> $request_lib,
            new_hold            => 1
		} 
	);
	return 0;
}



sub find_nearest_permitted_hold {

	my $class	= shift;
	my $editor	= shift; # CStoreEditor object
	my $copy		= shift; # copy to target
	my $user		= shift; # staff 
	my $check_only = shift; # do no updates, just see if the copy could fulfill a hold
	my $evt		= OpenILS::Event->new('ACTION_HOLD_REQUEST_NOT_FOUND');

	my $bc = $copy->barcode;

	# find any existing holds that already target this copy
	my $old_holds = $editor->search_action_hold_request(
		{	current_copy => $copy->id, 
			cancel_time => undef, 
			capture_time => undef 
		} 
	);

	# hold->type "R" means we need this copy
	for my $h (@$old_holds) { return ($h) if $h->hold_type eq 'R'; }


    my $hold_stall_interval = $U->ou_ancestor_setting_value($user->ws_ou, OILS_SETTING_HOLD_SOFT_STALL);

	$logger->info("circulator: searching for best hold at org ".$user->ws_ou.
        " and copy $bc with a hold stalling interval of ". ($hold_stall_interval || "(none)"));

	# search for what should be the best holds for this copy to fulfill
	my $best_holds = $U->storagereq(
		"open-ils.storage.action.hold_request.nearest_hold.atomic",
		$user->ws_ou, $copy->id, 10, $hold_stall_interval );

	unless(@$best_holds) {

		if( my $hold = $$old_holds[0] ) {
			$logger->info("circulator: using existing pre-targeted hold ".$hold->id." in hold search");
			return ($hold);
		}

		$logger->info("circulator: no suitable holds found for copy $bc");
		return (undef, $evt);
	}


	my $best_hold;

	# for each potential hold, we have to run the permit script
	# to make sure the hold is actually permitted.
	for my $holdid (@$best_holds) {
		next unless $holdid;
		$logger->info("circulator: checking if hold $holdid is permitted for copy $bc");

		my $hold = $editor->retrieve_action_hold_request($holdid) or next;
		my $reqr = $editor->retrieve_actor_user($hold->requestor) or next;
		my $rlib = $editor->retrieve_actor_org_unit($hold->request_lib) or next;

		# see if this hold is permitted
		my $permitted = OpenILS::Utils::PermitHold::permit_copy_hold(
			{	patron_id			=> $hold->usr,
				requestor			=> $reqr,
				copy				=> $copy,
				pickup_lib			=> $hold->pickup_lib,
				request_lib			=> $rlib,
			} 
		);

		if( $permitted ) {
			$best_hold = $hold;
			last;
		}
	}


	unless( $best_hold ) { # no "good" permitted holds were found
		if( my $hold = $$old_holds[0] ) { # can we return a pre-targeted hold?
			$logger->info("circulator: using existing pre-targeted hold ".$hold->id." in hold search");
			return ($hold);
		}

		# we got nuthin
		$logger->info("circulator: no suitable holds found for copy $bc");
		return (undef, $evt);
	}

	$logger->info("circulator: best hold ".$best_hold->id." found for copy $bc");

	# indicate a permitted hold was found
	return $best_hold if $check_only;

	# we've found a permitted hold.  we need to "grab" the copy 
	# to prevent re-targeted holds (next part) from re-grabbing the copy
	$best_hold->current_copy($copy->id);
	$editor->update_action_hold_request($best_hold) 
		or return (undef, $editor->event);


    my $retarget = 0;

	# re-target any other holds that already target this copy
	for my $old_hold (@$old_holds) {
		next if $old_hold->id eq $best_hold->id; # don't re-target the hold we want
		$logger->info("circulator: clearing current_copy and prev_check_time on hold ".
            $old_hold->id." after a better hold [".$best_hold->id."] was found");
        $old_hold->clear_current_copy;
        $old_hold->clear_prev_check_time;
        $editor->update_action_hold_request($old_hold) 
            or return (undef, $editor->event);
        $retarget = 1;
	}

	return ($best_hold, undef, $retarget);
}






__PACKAGE__->register_method(
	method => 'all_rec_holds',
	api_name => 'open-ils.circ.holds.retrieve_all_from_title',
);

sub all_rec_holds {
	my( $self, $conn, $auth, $title_id, $args ) = @_;

	my $e = new_editor(authtoken=>$auth);
	$e->checkauth or return $e->event;
	$e->allowed('VIEW_HOLD') or return $e->event;

	$args ||= { fulfillment_time => undef };
	$args->{cancel_time} = undef;

	my $resp = { volume_holds => [], copy_holds => [], metarecord_holds => [] };

    my $mr_map = $e->search_metabib_metarecord_source_map({source => $title_id})->[0];
    if($mr_map) {
        $resp->{metarecord_holds} = $e->search_action_hold_request(
            {   hold_type => OILS_HOLD_TYPE_METARECORD,
                target => $mr_map->metarecord,
                %$args 
            }, {idlist => 1}
        );
    }

	$resp->{title_holds} = $e->search_action_hold_request(
		{ 
			hold_type => OILS_HOLD_TYPE_TITLE, 
			target => $title_id, 
			%$args 
		}, {idlist=>1} );

	my $vols = $e->search_asset_call_number(
		{ record => $title_id, deleted => 'f' }, {idlist=>1});

	return $resp unless @$vols;

	$resp->{volume_holds} = $e->search_action_hold_request(
		{ 
			hold_type => OILS_HOLD_TYPE_VOLUME, 
			target => $vols,
			%$args }, 
		{idlist=>1} );

	my $copies = $e->search_asset_copy(
		{ call_number => $vols, deleted => 'f' }, {idlist=>1});

	return $resp unless @$copies;

	$resp->{copy_holds} = $e->search_action_hold_request(
		{ 
			hold_type => OILS_HOLD_TYPE_COPY,
			target => $copies,
			%$args }, 
		{idlist=>1} );

	return $resp;
}





__PACKAGE__->register_method(
	method => 'uber_hold',
    authoritative => 1,
	api_name => 'open-ils.circ.hold.details.retrieve'
);

sub uber_hold {
	my($self, $client, $auth, $hold_id) = @_;
	my $e = new_editor(authtoken=>$auth);
	$e->checkauth or return $e->event;
	$e->allowed('VIEW_HOLD') or return $e->event;

	my $resp = {};

	my $hold = $e->retrieve_action_hold_request(
		[
			$hold_id,
			{
				flesh => 1,
				flesh_fields => { ahr => [ 'current_copy', 'usr' ] }
			}
		]
	) or return $e->event;

	my $user = $hold->usr;
	$hold->usr($user->id);

	my $card = $e->retrieve_actor_card($user->card)
		or return $e->event;

	my( $mvr, $volume, $copy ) = find_hold_mvr($e, $hold);

	flesh_hold_notices([$hold], $e);
	flesh_hold_transits([$hold]);

	return {
		hold		=> $hold,
		copy		=> $copy,
		volume	=> $volume,
		mvr		=> $mvr,
		status	=> _hold_status($e, $hold),
		patron_first => $user->first_given_name,
		patron_last  => $user->family_name,
		patron_barcode => $card->barcode,
	};
}



# -----------------------------------------------------
# Returns the MVR object that represents what the
# hold is all about
# -----------------------------------------------------
sub find_hold_mvr {
	my( $e, $hold ) = @_;

	my $tid;
	my $copy;
	my $volume;

	if( $hold->hold_type eq OILS_HOLD_TYPE_METARECORD ) {
		my $mr = $e->retrieve_metabib_metarecord($hold->target)
			or return $e->event;
		$tid = $mr->master_record;

	} elsif( $hold->hold_type eq OILS_HOLD_TYPE_TITLE ) {
		$tid = $hold->target;

	} elsif( $hold->hold_type eq OILS_HOLD_TYPE_VOLUME ) {
		$volume = $e->retrieve_asset_call_number($hold->target)
			or return $e->event;
		$tid = $volume->record;

	} elsif( $hold->hold_type eq OILS_HOLD_TYPE_COPY ) {
		$copy = $e->retrieve_asset_copy($hold->target)
			or return $e->event;
		$volume = $e->retrieve_asset_call_number($copy->call_number)
			or return $e->event;
		$tid = $volume->record;
	}

	if(!$copy and ref $hold->current_copy ) {
		$copy = $hold->current_copy;
		$hold->current_copy($copy->id);
	}

	if(!$volume and $copy) {
		$volume = $e->retrieve_asset_call_number($copy->call_number);
	}

	my $title = $e->retrieve_biblio_record_entry($tid);
	return ( $U->record_to_mvr($title), $volume, $copy );
}




1;
