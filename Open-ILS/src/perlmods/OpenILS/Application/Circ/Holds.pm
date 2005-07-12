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
		"open-ils.storage.direct.action.hold_request.search.usr.atomic",
		$user_id );
	my $h = $req->gather(1);
	$session->disconnect();
	return $h;
}




1;
