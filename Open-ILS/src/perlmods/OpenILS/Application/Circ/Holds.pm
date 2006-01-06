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
use Data::Dumper;
use OpenILS::EX;
use OpenSRF::EX qw(:try);
use OpenILS::Perm;
use OpenILS::Event;
use OpenSRF::Utils::Logger qw(:logger);

my $apputils = "OpenILS::Application::AppUtils";



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

		#enforce the fact that the login is the one requesting the hold
		$hold->requestor($user->id); 

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

sub _check_request_holds_override {
	my $user_id = shift;
	my $org_id = shift;
	if(my $evt = $apputils->check_perms(
		$user_id, $org_id, "REQUEST_HOLDS_OVERRIDE")) {
		return $evt;
	}
}


__PACKAGE__->register_method(
	method	=> "retrieve_holds",
	api_name	=> "open-ils.circ.holds.retrieve",
	notes		=> <<NOTE);
Retrieves all the holds for the specified user id.  The login session
is the requestor and if the requestor is different from the user, then
the requestor must have VIEW_HOLD permissions.
NOTE


sub retrieve_holds {
	my($self, $client, $login_session, $user_id) = @_;

	my( $user, $target, $evt ) = $apputils->checkses_requestor(
		$login_session, $user_id, 'VIEW_HOLD' );
	return $evt if $evt;

	return $apputils->simplereq(
		'open-ils.storage',
		"open-ils.storage.direct.action.hold_request.search.atomic",
		"usr" =>  $user_id , fulfillment_time => undef, { order_by => "request_time" });
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
	my($self, $client, $login_session, $holdid) = @_;
	

	my $user = $apputils->check_user_session($login_session);
	my( $hold, $evt ) = $apputils->fetch_hold($holdid);
	return $evt if $evt;

	if($user->id ne $hold->usr) { #am I allowed to cancel this user's hold?
		if($evt = $apputils->checkperms(
			$user->id, $user->home_ou, 'CANCEL_HOLDS')) {
			return $evt;
		}
	}

	$logger->activity( "User " . $user->id . 
		" canceling hold $holdid for user " . $hold->usr );

	return $apputils->simplereq(
		'open-ils.storage',
		"open-ils.storage.direct.action.hold_request.delete", $hold );
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

	my( $requestor, $target, $evt ) = $apputils->checkses_requestor(
		$login_session, $hold->usr, 'UPDATE_HOLD' );
	return $evt if $evt;

	$logger->activity('User ' + $requestor->id . 
		' updating hold ' . $hold->id . ' for user ' . $target->id );

	return $apputils->simplereq(
		'open-ils.storage',
		"open-ils.storage.direct.action.hold_request.update", $hold );
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
	my($self, $client, $login_session, $hold_id) = @_;


	my( $requestor, $target, $hold, $copy, $transit, $evt );

	( $hold, $evt ) = $apputils->fetch_hold($hold_id);
	return $evt if $evt;

	( $requestor, $target, $evt ) = $apputils->checkses_requestor(
		$login_session, $hold->usr, 'VIEW_HOLD' );
	return $evt if $evt;

	return 1 unless (defined($hold->current_copy));
	
	( $copy, $evt ) = $apputils->fetch_copy($hold->current_copy);
	return $evt if $evt;

	return 4 if ($hold->capture_time and $copy->circ_lib eq $hold->pickup_lib);

	( $transit, $evt ) = $apputils->fetch_hold_transit_by_hold( $hold->id );
	return 4 if(ref($transit) and defined($transit->dest_recv_time) ); 

	return 3 if defined($hold->capture_time);

	return 2;
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

	my( $user, $target, $copy, $hold, $evt );

	( $user, $evt ) = $apputils->checkses($login_session);
	return $evt if $evt;

	# am I allowed to checkin a copy?
	$evt = $apputils->check_perms($user->id, $user->home_ou, "COPY_CHECKIN");
	return $evt if $evt;

	$logger->info("Capturing copy with barcode $barcode, flesh=$flesh");

	my $session = $apputils->start_db_session();

	($copy, $evt) = $apputils->fetch_copy_by_barcode($barcode);
	return $evt if $evt;

	$logger->debug("Capturing copy " . $copy->id);

	( $hold, $evt ) = _find_local_hold_for_copy($session, $copy, $user);
	return $evt if $evt;

	warn "Found hold " . $hold->id . "\n";
	$logger->info("We found a hold " .$hold->id. "for capturing copy with barcode $barcode");

	$hold->current_copy($copy->id);
	$hold->capture_time("now"); 

	#update the hold
	my $stat = $session->request(
			"open-ils.storage.direct.action.hold_request.update", $hold)->gather(1);
	if(!$stat) { throw OpenSRF::EX::ERROR 
		("Error updating hold request " . $copy->id); }

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
		($title, $evt) = $apputils->fetch_record_by_copy( $copy->id );
		return $evt if $evt;
		$title = $apputils->record_to_mvr($title);
	} 

	$apputils->commit_db_session($session);

	my $payload = { copy => $copy, record => $title, hold => $hold, };

	return OpenILS::Event->new('ROUTE_COPY', route_to => $hold->pickup_lib, payload => $payload );
}

sub _build_hold_transit {
	my( $self, $login_session, $session, $hold, $user, $copy ) = @_;
	my $trans = Fieldmapper::action::hold_transit_copy->new;

	$trans->hold($hold->id);
	$trans->source($user->home_ou);
	$trans->dest($hold->pickup_lib);
	$trans->source_send_time("now");
	$trans->target_copy($copy->id);
	$trans->copy_status($copy->status);

	my $meth = $self->method_lookup("open-ils.circ.hold_transit.create");
	my ($stat) = $meth->run( $login_session, $trans, $session );
	if(!$stat) { throw OpenSRF::EX ("Error creating new hold transit"); }
	else { $copy->status(6); } #status in transit 
}


sub _find_local_hold_for_copy {

	my $session = shift;
	my $copy = shift;
	my $user = shift;
	my $evt = OpenILS::Event->new('HOLD_NOT_FOUND');

	# first see if this copy has already been selected to fulfill a hold
	my $hold  = $session->request(
		"open-ils.storage.direct.action.hold_request.search_where",
		{ current_copy => $copy->id, capture_time => undef } )->gather(1);

	$logger->debug("Hold found for copy " . $copy->id);

	if($hold) {return $hold;}

	$logger->debug("searching for local hold at org " . 
		$user->home_ou . " and copy " . $copy->id);

	my $holdid = $session->request(
		"open-ils.storage.action.hold_request.nearest_hold",
		$user->home_ou, $copy->id )->gather(1);

	return (undef, $evt) unless defined $holdid;

	$logger->debug("Found hold id $holdid while ".
		"searching nearest hold to " .$user->home_ou);

	return $apputils->fetch_hold($holdid);
}


__PACKAGE__->register_method(
	method	=> "create_hold_transit",
	api_name	=> "open-ils.circ.hold_transit.create",
	notes		=> <<"	NOTE");
	Creates a new transit object
	NOTE

sub create_hold_transit {
	my( $self, $client, $login_session, $transit, $session ) = @_;

	my( $user, $evt ) = $apputils->checkses($login_session);
	return $evt if $evt;
	$evt = $apputils->check_perms($user->id, $user->home_ou, "CREATE_TRANSIT");
	return $evt if $evt;

	my $ses;
	if($session) { $ses = $session; } 
	else { $ses = OpenSRF::AppSession->create("open-ils.storage"); }

	return $ses->request(
		"open-ils.storage.direct.action.hold_transit_copy.create", $transit )->gather(1);
}


sub fetch_open_hold_by_current_copy {
	my $class = shift;
	my $copyid = shift;
	my $hold = $apputils->simplereq(
		'open-ils.storage', 
		'open-ils.storage.direct.action.hold_request.search.atomic',
			 current_copy =>  $copyid , fulfillment_time => undef );
	return $hold->[0] if ref($hold);
	return undef;
}


1;
