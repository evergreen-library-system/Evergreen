package OpenILS::Application::Search;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::ModsParser;

use OpenILS::Application::Search::StaffClient;
use OpenILS::Application::Search::Web;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);

# Houses generic search utilites 



__PACKAGE__->register_method(
	method	=> "biblio_search_marc",
	api_name	=> "open-ils.search.biblio.marc",
	argc		=> 1, 
	note		=> "Searches biblio information by marc tag",
);

sub biblio_search_marc {

	my( $self, $client, $search_hash, $string ) = @_;

	warn "Building biblio marc session\n";
	my $session = OpenSRF::AppSession->create("open-ils.storage");

	warn "Sending biblio marc request\n";
	my $request = $session->request( 
			"open-ils.storage.metabib.full_rec.search_fts.index_vector", 
			$search_hash, $string );

	warn "Waiting complete\n";
	$request->wait_complete();

	warn "Calling recv\n";
	my $response = $request->recv();

	warn "out of recv\n";
	if($response and UNIVERSAL::isa($response,"OpenSRF::EX")) {
		throw $response ($response->stringify);
	}


	my $data = [];
	if($response and UNIVERSAL::can($response,"content")) {
		$data = $response->content;
	}
	warn "finishing request\n";

	$request->finish();
	$session->finish();
	$session->disconnect();

	return $data;

}



__PACKAGE__->register_method(
	method	=> "get_org_tree",
	api_name	=> "open-ils.search.actor.org_tree.retrieve",
	argc		=> 1, 
	note		=> "Returns the entire org tree structure",
);

sub get_org_tree {

	my( $self, $client, $user_session ) = @_;

	if( $user_session ) { # keep for now for backwards compatibility

		my $user_obj = 
			OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error
		
		my $session = OpenSRF::AppSession->create("open-ils.storage");
		my $request = $session->request( 
				"open-ils.storage.actor.org_unit.retrieve", $user_obj->home_ou );
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

	return OpenILS::Application::AppUtils->get_org_tree();
}



__PACKAGE__->register_method(
	method	=> "get_org_sub_tree",
	api_name	=> "open-ils.search.actor.org_subtree.retrieve",
	argc		=> 1, 
	note		=> "Returns the entire org tree structure",
);

sub get_sub_org_tree {

	my( $self, $client, $user_session ) = @_;

	if(!$user_session) {
		throw OpenSRF::EX::InvalidArg 
			("No User session provided to org_subtree.retrieve");
	}

	if( $user_session ) {

		my $user_obj = 
			OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

		
		my $session = OpenSRF::AppSession->create("open-ils.storage");
		my $request = $session->request( 
				"open-ils.storage.actor.org_unit.retrieve", $user_obj->home_ou );
		my $response = $request->recv();

		if(!$response) { 
			throw OpenSRF::EX::ERROR (
					"No response from storage for org_unit retrieve");
		}
		if(UNIVERSAL::isa($response,"Error")) {
			throw $response ($response->stringify);
		}

		my $home_ou = $response->content;

		# XXX grab descendants and build org tree from them
=head comment
		my $request = $session->request( 
				"open-ils.storage.actor.org_unit_descendants" );
		my $response = $request->recv();
		if(!$response) { 
			throw OpenSRF::EX::ERROR (
					"No response from storage for org_unit retrieve");
		}
		if(UNIVERSAL::isa($response,"Error")) {
			throw $response ($response->stringify);
		}

		my $descendants = $response->content;
=cut

		$request->finish();
		$session->disconnect();

		return $home_ou;
	}

	return undef;

}




# ---------------------------------------------------------------------------
# takes a list of record id's and turns the docs into friendly 
# mods structures. Creates one MODS structure for each doc id.
# ---------------------------------------------------------------------------
sub _records_to_mods {
	my @ids = @_;
	
	my @results;
	my @marcxml_objs;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $request = $session->request(
			"open-ils.storage.biblio.record_marc.batch.retrieve",  @ids );

	my $last_content = undef;

	while( my $response = $request->recv() ) {

		if( $last_content ) {
			my $u = OpenILS::Utils::ModsParser->new();
			$u->start_mods_batch( $last_content->marc );
			my $mods = $u->finish_mods_batch();
			$mods->{doc_id} = $last_content->id();
			warn "Turning doc " . $mods->{doc_id} . " into MODS\n";
			$last_content = undef;
			push @results, $mods;
		}

		next unless $response;

		if($response->isa("OpenSRF::EX")) {
			throw $response ($response->stringify);
		}

		$last_content = $response->content;

	}

	if( $last_content ) {
		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch( $last_content->marc );
		my $mods = $u->finish_mods_batch();
		$mods->{doc_id} = $last_content->id();
		push @results, $mods;
	}

	$request->finish();
	$session->finish();
	$session->disconnect();

	return \@results;

}

__PACKAGE__->register_method(
	method	=> "record_id_to_mods",
	api_name	=> "open-ils.search.biblio.record.mods.retrieve",
	argc		=> 1, 
	note		=> "Provide ID, we provide the mods"
);

# converts a record into a mods object with copy counts attached
sub record_id_to_mods {

	my( $self, $client, $org_id, $id ) = @_;

	my $mods_list = _records_to_mods( $id );
	my $mods_obj = $mods_list->[0];

	# --------------------------------------------------------------- # append copy count information to the mods objects
	my $session = OpenSRF::AppSession->create("open-ils.storage");

	warn "mods retrieve $id\n";

	my $request = $session->request(
		"open-ils.storage.biblio.record_copy_count",  $org_id, $id );
	warn "mods retrieve wait $id\n";
	$request->wait_complete;
	warn "mods retrieve recv $id\n";
	my $response = $request->recv();
	return undef unless $response;
	warn "mods retrieve after recv $id\n";

	if( $response and UNIVERSAL::isa($response, "Error")) {
		throw $response ($response->stringify);
	}

	my $count = $response->content;
	$mods_obj->{copy_count} = $count;

	$request->finish();
	$session->finish();
	$session->disconnect();

	return $mods_obj;
}




1;
