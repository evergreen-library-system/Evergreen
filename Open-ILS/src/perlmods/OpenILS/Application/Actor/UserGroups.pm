package OpenILS::Application::Actor::UserGroups;
use base 'OpenSRF::Application';
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Editor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenSRF::EX qw(:try);
my $U = "OpenILS::Application::AppUtils";

sub initialize { return 1; }


__PACKAGE__->register_method(
	method => 'get_users_from_usergroup',
	api_name	=> 'open-ils.actor.usergroup.members.retrieve',
	signature	=> q/
		Returns a list of ids for users that are in the given usergroup
	/
);

sub get_users_from_usergroup {
	my( $self, $conn, $auth, $usergroup ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_USER'); # XXX reley on editor perm
	return $e->search_actor_user({usrgroup => $usergroup}, {idlist => 1});
}



__PACKAGE__->register_method(
	method => 'get_leaders_from_usergroup',
	api_name	=> 'open-ils.actor.usergroup.leaders.retrieve',
	signature	=> q/
		Returns a list of ids for users that are leaders of the given usergroup
	/
);

sub get_leaders_from_usergroup {
	my( $self, $conn, $auth, $usergroup ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_USER'); # XXX reley on editor perm
	my $users = $e->search_actor_user({usrgroup => $usergroup})
		or return $e->event;

	my @res;
	for my $u (@$users) {
		push( @res, $u->id ) if $u->master_account;
	}

	return \@res;
}



__PACKAGE__->register_method(
	method => 'get_address_members',
	api_name	=> 'open-ils.actor.address.members',
	signature	=> q/
		Returns a list of ids for users that link to the given address
		@param auth
		@param addrid The address id
	/
);

sub get_address_members {
	my( $self, $conn, $auth, $addrid ) = @_;

	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_USER'); # XXX reley on editor perm

	my $ad = $e->retrieve_actor_user_address($addrid) or return $e->event;
	my $ma = $e->search_actor_user({mailing_address => $addrid}, {idlist => 1});
	my $ba = $e->search_actor_user({billing_address => $addrid}, {idlist => 1});

	my @list = (@$ma, @$ba, $ad->usr);
	my %dedup = map { $_ => 1 } @list;
	return [ keys %dedup ];
}



__PACKAGE__->register_method(
	method	=> 'reset_group',
	api_name	=> 'open-ils.actor.usergroup.new',
	signature	=> q/
		Gives the requested user a new empty usergroup.  
		@param auth The auth token
		@param userid The id of the user who needs the new usergroup
		@param leader If true, this user will be marked as the group leader
	/
);

sub reset_group {
	my( $self, $conn, $auth, $userid, $leader ) = @_;

	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('UPDATE_USER'); # XXX reley on editor perm

	my $user = $e->retrieve_actor_user($userid) or return $e->event;

	# ask for a new group id
	my $groupid = $e->request('open-ils.storage.actor.user.group_id.new');

	$user->usrgroup($groupid);
	$user->master_account('t') if $leader;

	$e->update_actor_user($user) or return $e->event;
	$e->commit;
	return $groupid;
}




1;
