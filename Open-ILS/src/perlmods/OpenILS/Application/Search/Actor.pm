package OpenILS::Application::Search::Actor;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use OpenILS::Application::AppUtils;



__PACKAGE__->register_method(
	method	=> "actor_user_search_username",
	api_name	=> "open-ils.search.actor.user.search.username",
);

sub actor_user_search_username {

	my($self, $client, $username) = @_;

	my $users = OpenILS::Application::AppUtils->simple_scalar_request(
			"open-ils.storage", 
			"open-ils.storage.direct.actor.user.search.usrname",
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

	my $user = OpenILS::Application::AppUtils->simple_scalar_request(
			'open-ils.storage', 
			'open-ils.storage.fleshed.actor.user.search.barcode.atomic',
			$barcode,
			);

	return $user->[0];

}

1;
