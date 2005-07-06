package OpenILS::Application::Search::Actor;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";



__PACKAGE__->register_method(
	method	=> "actor_user_search_username",
	api_name	=> "open-ils.search.actor.user.search.username",
);

sub actor_user_search_username {

	my($self, $client, $username) = @_;

	my $users = OpenILS::Application::AppUtils->simple_scalar_request(
			"open-ils.storage", 
			"open-ils.storage.direct.actor.user.search.usrname.atomic",
			$username );

	return $users;
}


__PACKAGE__->register_method(
	method	=> "actor_user_retrieve_by_barcode",
	api_name	=> "open-ils.search.actor.user.barcode",
);

sub actor_user_retrieve_by_barcode {
	my($self, $client, $barcode) = @_;
	warn "Searching for user with barcode $barcode\n";

	my $session = OpenSRF::AppSession->create("open-ils.storage");

	# find the card with the given barcode
	my $creq	= $session->request(
			"open-ils.storage.direct.actor.card.search.barcode.atomic",
			$barcode );
	my $card = $creq->gather(1);
	$card = $card->[0];
	my $user = flesh_user($card->usr(), $session);
	$session->disconnect();
	return $user;

}


__PACKAGE__->register_method(
	method	=> "actor_user_retrieve_by_session",
	api_name	=> "open-ils.search.actor.user.session",
);

sub actor_user_retrieve_by_session {
	my($self, $client, $user_session) = @_;
	warn "Searching for user with user_session $user_session\n";
	my $user_obj = $apputils->check_user_session($user_session);
	my $session = OpenSRF::AppSession->create("open-ils.storage");
	return flesh_user($user_obj->id);
}


sub flesh_user {
	my $id = shift;
	my $session = shift;
	my $kill = 0;

	if(!$session) {
		$session = OpenSRF::AppSession->create("open-ils.storage");
		$kill = 1;
	}

	# grab the user with the given card
	my $ureq = $session->request(
			"open-ils.storage.direct.actor.user.retrieve",
			$id);
	my $user = $ureq->gather(1);

	# grab the cards
	my $cards_req = $session->request(
			"open-ils.storage.direct.actor.card.search.usr.atomic",
			$user->id() );
	$user->cards( $cards_req->gather(1) );

	my $add_req = $session->request(
			"open-ils.storage.direct.actor.user_address.search.usr.atomic",
			$user->id() );
	$user->addresses( $add_req->gather(1) );

	if($kill) { $session->disconnect(); }

	return $user;

}


__PACKAGE__->register_method(
	method	=> "get_org_tree",
	api_name	=> "open-ils.search.actor.org_tree.retrieve",
	argc		=> 1, 
	note		=> "Returns the entire org tree structure",
);

sub get_org_tree {

	my( $self, $client, $user_session ) = @_;

=head
	if( $user_session ) { # keep for now for backwards compatibility

		my $user_obj = 
			OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error
		
		my $session = OpenSRF::AppSession->create("open-ils.storage");
		my $request = $session->request( 
				"open-ils.storage.direct.actor.org_unit.retrieve", $user_obj->home_ou );
		my $response = $request->recv();

		if(!$response) { 
			throw OpenSRF::EX::ERROR (
					"No response from storage for org_unit retrieve");
		}
		if(UNIVERSAL::isa($response,"Error")) {
			throw $response ($response->stringify);
		}

		my $home_ou = $response->content;
		$request->finish();
		$session->disconnect();

		return $home_ou;
	}
=cut

	warn "Getting ORG Tree\n";
	my $org_tree = OpenILS::Application::AppUtils->get_org_tree();
	warn "Returning Org Tree\n";

	return $org_tree;
}


__PACKAGE__->register_method(
	method	=> "get_org_tree_slim",
	api_name	=> "open-ils.search.actor.org_tree.slim.retrieve",
	argc		=> 1, 
	note		=> "Returns the entire org tree structure",
);

sub get_org_tree_slim {
	my( $self, $client, $user_session ) = @_;
	warn "Getting ORG Tree\n";
	warn "Call: " . $self->api_name() . "\n";
	return OpenILS::Application::AppUtils->get_slim_org_tree();
}






__PACKAGE__->register_method(
	method	=> "get_org_types",
	api_name	=> "open-ils.search.actor.org_types.retrieve",
);

sub get_org_types {
	my($self, $client) = @_;

	 my $org_typelist = OpenILS::Application::AppUtils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.actor.org_unit_type.retrieve.all.atomic" );

	 return $org_typelist;
}


__PACKAGE__->register_method(
	method	=> "get_user_profiles",
	api_name	=> "open-ils.search.actor.user.profiles.retrieve",
);
sub get_user_profiles {
	return OpenILS::Application::AppUtils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.actor.profile.retrieve.all.atomic",
			( "1", "2", "3" ) );
}



__PACKAGE__->register_method(
	method	=> "get_user_ident_types",
	api_name	=> "open-ils.search.actor.user.ident_types.retrieve",
);
sub get_user_ident_types {
	return OpenILS::Application::AppUtils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.config.identification_type.retrieve.all.atomic" );
}




__PACKAGE__->register_method(
	method	=> "get_org_unit",
	api_name	=> "open-ils.search.actor.org_unit.retrieve",
	argc		=> 1, 
	note		=> "Returns the entire org tree structure",
);

sub get_org_unit {

	my( $self, $client, $user_session ) = @_;

	my $user_obj = 
		OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

	my $home_ou = OpenILS::Application::AppUtils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.actor.org_unit.retrieve", 
		$user_obj->home_ou );

	return $home_ou;
}




1;
