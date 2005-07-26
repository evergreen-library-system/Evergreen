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
use base qw/OpenSRF::Application/;
use strict; use warnings;
use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
use OpenILS::EX;
use OpenSRF::EX qw(:try);
use OpenILS::Perm;



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

sub create_hold {
	my( $self, $client, $login_session, @holds) = @_;

	if(!@holds){return 0;}
	my $user = $apputils->check_user_session($login_session);


	my $holds;
	if(ref($holds[0]) eq 'ARRAY') {
		$holds = $holds[0];
	} else { $holds = [ @holds ]; }

	warn "Iterating over holds requests...\n";

	for my $hold (@$holds) {

		if(!$hold){next};
		my $type = $hold->hold_type;

		use Data::Dumper;
		warn "Hold to create: " . Dumper($hold) . "\n";

		my $recipient;
		if($user->id ne $hold->usr) {

		} else {
			$recipient = $user;
		}

		#enforce the fact that the login is the one requesting the hold
		$hold->requestor($user->id); 

		my $perm = undef;

		# see if the requestor even has permission to request
		if($hold->requestor ne $hold->usr) {
			$perm = _check_request_holds_perm($type, $user->id, $user->home_ou);
			if($perm) { return $perm; }
		}

		$perm = _check_holds_perm($type, $hold->usr, $recipient->home_ou);
		if($perm) { 
			#if there is a requestor, see if the requestor has override privelages
			if($hold->requestor ne $hold->usr) {
				$perm = _check_request_holds_override($user->id, $user->home_ou);
				if($perm) {return $perm;}
			} else {
				return $perm; 
			}
		}


		#my $session = $apputils->start_db_session();
		my $session = OpenSRF::AppSession->create("open-ils.storage");
		my $method = "open-ils.storage.direct.action.hold_request.create";
		warn "Sending hold request to storage... $method \n";

		my $req = $session->request( $method, $hold );

		my $resp = $req->gather(1);
		$session->disconnect();
		if(!$resp) { return OpenILS::EX->new("UNKNOWN")->ex(); }
#		$apputils->commit_db_session($session);
	}

	return 1;
}

# makes sure that a user has permission to place the type of requested hold
# returns the Perm exception if not allowed, returns undef if all is well
sub _check_holds_perm {
	my($type, $user_id, $org_id) = @_;

	if($type eq "M") {
		if($apputils->check_user_perms($user_id, $org_id, "MR_HOLDS")) {
			return OpenILS::Perm->new("MR_HOLDS");
		} 

	} elsif ($type eq "T") {
		if($apputils->check_user_perms($user_id, $org_id, "TITLE_HOLDS")) {
			return OpenILS::Perm->new("TITLE_HOLDS");
		}

	} elsif($type eq "V") {
		if($apputils->check_user_perms($user_id, $org_id, "VOLUME_HOLDS")) {
			return OpenILS::Perm->new("VOLUME_HOLDS");
		}

	} elsif($type eq "C") {
		if($apputils->check_user_perms($user_id, $org_id, "COPY_HOLDS")) {
			return OpenILS::Perm->new("COPY_HOLDS");
		}
	}

	return undef;
}

# tests if the given user is allowed to place holds on another's behalf
sub _check_request_holds_perm {
	my $user_id = shift;
	my $org_id = shift;
	if($apputils->check_user_perms($user_id, $org_id, "REQUEST_HOLDS")) {
		return OpenILS::Perm->new("REQUEST_HOLDS");
	}
}

sub _check_request_holds_override {
	my $user_id = shift;
	my $org_id = shift;
	if($apputils->check_user_perms($user_id, $org_id, "REQUEST_HOLDS_OVERRIDE")) {
		return OpenILS::Perm->new("REQUEST_HOLDS_OVERRIDE");
	}
}


__PACKAGE__->register_method(
	method	=> "retrieve_holds",
	api_name	=> "open-ils.circ.holds.retrieve",
	notes		=> <<NOTE);
Retrieves all the holds for the specified user id.  The login session
is the requestor and if the requestor is different from the user, then
the requestor must have VIEW_HOLDS permissions.
NOTE


sub retrieve_holds {
	my($self, $client, $login_session, $user_id) = @_;

	my $user = $apputils->check_user_session($login_session);

	if($user->id ne $user_id) {
		if($apputils->check_user_perms($user->id, $user->home_ou, "VIEW_HOLDS")) {
			return OpenILS::Perm->new("VIEW_HOLDS");
		}
	}

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $req = $session->request(
		"open-ils.storage.direct.action.hold_request.search.atomic",
		"usr" =>  $user_id , fulfillment_time => undef, { order_by => "request_time" });

	my $h = $req->gather(1);
	$session->disconnect();
	return $h;
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
	my($self, $client, $login_session, $hold) = @_;

	my $user = $apputils->check_user_session($login_session);

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	
	if(!ref($hold)) {
		$hold = $session->request(
			"open-ils.storage.direct.action.hold_request.retrieve", $hold)->gather(1);
	}

	if($user->id ne $hold->usr) {
		if($apputils->check_user_perms($user->id, $user->home_ou, "CANCEL_HOLDS")) {
			return OpenILS::Perm->new("CANCEL_HOLDS");
		}
	}

	use Data::Dumper;
	warn "Cancelling hold: " . Dumper($hold) . "\n";

	my $req = $session->request(
		"open-ils.storage.direct.action.hold_request.delete",
		$hold );
	my $h = $req->gather(1);

	warn "[$h] returned from hold_request delete\n";
	$session->disconnect();
	return $h;
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
	my($self, $client, $login_session, $hold) = @_;

	my $user = $apputils->check_user_session($login_session);

	if($user->id ne $hold->usr) {
		if($apputils->check_user_perms($user->id, $user->home_ou, "UPDATE_HOLDS")) {
			return OpenILS::Perm->new("UPDATE_HOLDS");
		}
	}

	use Data::Dumper;
	warn "Updating hold: " . Dumper($hold) . "\n";

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $req = $session->request(
		"open-ils.storage.direct.action.hold_request.update", $hold );
	my $h = $req->gather(1);

	warn "[$h] returned from hold_request update\n";
	$session->disconnect();
	return $h;
}


__PACKAGE__->register_method(
	method	=> "retrieve_hold_status",
	api_name	=> "open-ils.circ.hold.status.retrieve",
	notes		=> <<"	NOTE");
	Calculates the current status of the hold.
	the requestor must have VIEW_HOLDS permissions if the hold is for a user
	other than the requestor.
	Returns -1  on error (for now)
	Returns 1 for 'waiting for copy to become available'
	Returns 2 for 'waiting for copy capture'
	Returns 3 for 'in transit'
	Returns 4 for 'arrived'
	NOTE

sub retrieve_hold_status {
	my($self, $client, $login_session, $hold_id) = @_;

	my $user = $apputils->check_user_session($login_session);

	my $session = OpenSRF::AppSession->create("open-ils.storage");

	my $hold = $session->request(
		"open-ils.storage.direct.action.hold_request.retrieve", $hold_id )->gather(1);
	return -1 unless $hold; # should be an exception


	if($user->id ne $hold->usr) {
		if($apputils->check_user_perms($user->id, $user->home_ou, "VIEW_HOLDS")) {
			return OpenILS::Perm->new("VIEW_HOLDS");
		}
	}
	
	return 1 unless (defined($hold->current_copy));

	#return 2 unless (defined($hold->capture_time));

	my $copy = $session->request(
		"open-ils.storage.direct.asset.copy.retrieve", $hold->current_copy )->gather(1);
	return 1 unless $copy; # should be an exception

	use Data::Dumper;
	warn "Hold Copy in status check: " . Dumper($copy) . "\n\n";

	return 4 if ($hold->capture_time and $copy->circ_lib eq $hold->pickup_lib);

	my $transit = _fetch_hold_transit($session, $hold->id);
	return 4 if(ref($transit) and defined($transit->dest_recv_time) ); 

	return 3 if defined($hold->capture_time);

	return 2;
}


sub _fetch_hold_transit {
	my $session = shift;
	my $holdid = shift;
	return $session->request(
		"open-ils.storage.direct.action.hold_transit_copy.search.hold",
		$holdid )->gather(1);
}

__PACKAGE__->register_method(
	method	=> "capture_copy",
	api_name	=> "open-ils.circ.hold.capture_copy.barcode",
	notes		=> <<"	NOTE");
	Captures a copy to fulfil a hold
	Params is login session and copy barcode
	Optional param is 'flesh'.  If set, we also return the
	relevant copy and title
	login mus have COPY_CHECKIN permissions (since this is essentially
	copy checkin)
	NOTE

sub capture_copy {
	my( $self, $client, $login_session, $barcode, $flesh ) = @_;

	warn "Capturing copy with barcode $barcode, flesh=$flesh \n";

	my $user = $apputils->check_user_session($login_session);

	if($apputils->check_user_perms($user->id, $user->home_ou, "COPY_CHECKIN")) {
		return OpenILS::Perm->new("COPY_CHECKIN"); }

	my $session = $apputils->start_db_session();

	my $copy = $session->request(
		"open-ils.storage.direct.asset.copy.search.barcode",
		$barcode )->gather(1);

	warn "Found copy $copy\n";

	return OpenILS::EX->new("UNKNOWN_BARCODE")->ex unless $copy;

	warn "Capturing copy " . $copy->id . "\n";

	my $hold = _find_local_hold_for_copy($session, $copy, $user);
	if(!$hold) {return OpenILS::EX->new("NO_HOLD_FOUND")->ex;}

	warn "Found hold " . $hold->id . "\n";

	$hold->current_copy($copy->id);
	$hold->capture_time("now"); 

	#update the hold
	my $stat = $session->request(
			"open-ils.storage.direct.action.hold_request.update", $hold)->gather(1);
	if(!$stat) { throw OpenSRF::EX ("Error updating hold request " . $copy->id); }

	$copy->status(8); #status on holds shelf

	# if the staff member capturing this item is not at the pickup lib
	if( $user->home_ou ne $hold->pickup_lib ) {
		$self->_build_hold_transit( $login_session, $session, $hold, $user, $copy );
	}

	$copy->editor($user->id);
	$copy->edit_date("now");
	$stat = $session->request(
		"open-ils.storage.direct.asset.copy.update", $copy )->gather(1);
	if(!$stat) { throw OpenSRF::EX ("Error updating copy " . $copy->id); }

	
	my $title = undef;
	if($flesh) {
		$title = $session->request(
			"open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy",
			$copy->id )->gather(1);
		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch( $title->marc() );
		$title = $u->finish_mods_batch();

	} 

	$apputils->commit_db_session($session);

	return { 
		copy => $copy,
		route_to => $hold->pickup_lib,
		record => $title,
		hold => $hold, 
	};

}

sub _build_hold_transit {
	my( $self, $login_session, $session, $hold, $user, $copy ) = @_;
	my $trans = Fieldmapper::action::hold_transit_copy->new;
	$trans->hold($hold->id);
	$trans->source($user->home_ou);
	$trans->dest($hold->pickup_lib);
	$trans->source_send_time("now");
	$trans->target_copy($copy->id);
	my $meth = $self->method_lookup("open-ils.circ.hold_transit.create");
	my ($stat) = $meth->run( $login_session, $trans, $session );
	if(!$stat) { throw OpenSRF::EX ("Error creating new hold transit"); }
	else { $copy->status(6); } #status in transit 
}


sub _find_local_hold_for_copy {

	my $session = shift;
	my $copy = shift;
	my $user = shift;

	# first see if this copy has already been selected to fulfill a hold
	my $hold  = $session->request(
		"open-ils.storage.direct.action.hold_request.search_where",
		{ current_copy => $copy->id, capture_time => undef } )->gather(1);

	if($hold) {return $hold;}

	warn "searching for local hold at org " . $user->home_ou . " and copy " . $copy->id . "\n";

	my $holdid = $session->request(
		"open-ils.storage.action.hold_request.nearest_hold",
		$user->home_ou, $copy->id )->gather(1);

	if(!$holdid) { return undef; }

	warn "found hold id $holdid\n";

	return $session->request(
		"open-ils.storage.direct.action.hold_request.retrieve", $holdid )->gather(1);

}


__PACKAGE__->register_method(
	method	=> "create_hold_transit",
	api_name	=> "open-ils.circ.hold_transit.create",
	notes		=> <<"	NOTE");
	Creates a new transit object
	NOTE

sub create_hold_transit {
	my( $self, $client, $login_session, $transit, $session ) = @_;

	my $user = $apputils->check_user_session($login_session);
	if($apputils->check_user_perms($user->id, $user->home_ou, "CREATE_TRANSIT")) {
		return OpenILS::Perm->new("CREATE_TRANSIT");
	}
	
	my $ses;
	if($session) { $ses = $session; } 
	else { $ses = OpenSRF::AppSession->create("open-ils.storage"); }

	return $ses->request(
		"open-ils.storage.direct.action.hold_transit_copy.create", $transit )->gather(1);
}




1;
