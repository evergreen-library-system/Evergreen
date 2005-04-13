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

	use Data::Dumper;
	warn Dumper $users;
	return $users;
}


__PACKAGE__->register_method(
	method	=> "actor_user_search_barcode",
	api_name	=> "open-ils.search.actor.user.barcode",
);


sub actor_user_search_barcode {
	my($self, $client, $barcode) = @_;
	warn "Searching for user with barcode $barcode\n";

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $req = $session->request(
		"open-ils.storage.direct.actor.card.search.barcode",
		$barcode);

	throw $req->failed if( $req->failed);

	my $resp = $req->recv;
	my $cards = $resp->content;

	$req->finish();
	$session->finish();

	my @users;
	if(!$cards) { return undef; }

	use Data::Dumper;
	warn Dumper $cards;

	for my $card (@$cards) {
		my $user = $self->flesh_out_usr_1( $card->usr(), $session );
		$user->card($card);
		push @users, $user;
	}

	$session->disconnect();
	return \@users;

}

sub flesh_out_usr_1 {
	my($self,$usrid,$session) = @_;

	my $kill = undef;
	if(!$session) {
		$session = OpenSRF::AppSession->create("open-ils.storage");
	} else { $kill = 1; }

	my $req = $session->request(
			"open-ils.storage.direct.actor.user.retrieve",
			$usrid);

	throw $req->failed if( $req->failed);

	if($kill) {
		$session->finish();
		$session->disconnect();
	}

	my $resp = $req->recv;
	return $resp->content;

	#XXX we need to grab the primary address

}



1;
