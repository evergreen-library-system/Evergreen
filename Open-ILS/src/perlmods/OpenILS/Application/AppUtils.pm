package OpenILS::Application::AppUtils;
use strict; use warnings;
use base qw/OpenSRF::Application/;


# ---------------------------------------------------------------------------
# Pile of utilty methods used accross applications.
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# on sucess, returns the created session, on failure throws ERROR exception
# ---------------------------------------------------------------------------
sub start_db_session {
	my $self = shift;
	my $session = OpenSRF::AppSession->connect( "open-ils.storage" );
	my $trans_req = $session->request( "open-ils.storage.transaction.begin" );
	my $trans_resp = $trans_req->recv();
	if(ref($trans_resp) and $trans_resp->isa("Error")) { throw $trans_resp; }
	if( ! $trans_resp->content() ) {
		throw OpenSRF::ERROR ("Unable to Begin Transaction with database" );
	}
	$trans_req->finish();
	return $session;
}

# ---------------------------------------------------------------------------
# commits and destroys the session
# ---------------------------------------------------------------------------
sub commit_db_session {
	my( $self, $session ) = @_;

	my $req = $session->request( "open-ils.storage.transaction.commit" );
	my $resp = $req->recv();
	if(ref($resp) and $resp->isa("Error")) { throw $resp; }

	$session->finish();
	$session->disconnect();
	$session->kill_me();
}



# ---------------------------------------------------------------------------
# Checks to see if a user is logged in.  Returns the user record on success,
# throws an exception on error.
# ---------------------------------------------------------------------------
sub check_user_session {

	my( $self, $user_session ) = @_;
	my $session = OpenSRF::AppSession->create( "open-ils.auth" );
	my $request = $session->request("open-ils.auth.session.retrieve", $user_session );
	my $response = $request->recv();
	if($response) {
		throw OpenSRF::EX::ERROR ("Session [$user_session] cannot be authenticated" );
	}
	if($response->isa("OpenSRF::EX")) {
		throw $response ($response->stringify);
	}

	my $user = $response->content;
	if(!$user ) {
		throw OpenSRF::EX::ERROR ("Session [$user_session] cannot be authenticated" );
	}

	$session->disconnect();
	$session->kill_me();

	return $user;


=head blah
	my $method = $self->method_lookup("open-ils.auth.session.retrieve");
	if(!$method) {
		throw OpenSRF::EX::PANIC ("Can't locate method 'open-ils.auth.session.retrieve'" );
	}

	my ($user) = $method->run( $user_session );
	if(!$user ) {
		throw OpenSRF::EX::ERROR ("Session [$user_session] cannot be authenticated" );
	}
	return $user;
=cut
	
}



1;
