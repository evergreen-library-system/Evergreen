package OpenILS::Application::Search;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenILS::Utils::Fieldmapper;
use Time::HiRes qw(time);
use OpenILS::Application::Cat::Utils;

use OpenSRF::EX qw(:try);

# used for cat search classes
my $cat_search_hash =  {

	author => [ 
		{ tag => "100", subfield => "a"} ,
		{ tag => "700", subfield => "a"}, 
	],

	title => [ 
		{ tag => "245", subfield => "a"},
		{ tag => "242", subfield => "a"}, 
		{ tag => "240", subfield => "a"},
		{ tag => "210", subfield => "a"},
	],

	subject => [ 
		{ tag => "650", subfield => "_" }, 
	],

	tcn	=> [
		{ tag => "035", subfield => "_" },
	],

};


__PACKAGE__->register_method(
	method	=> "cat_biblio_search_tcn",
	api_name	=> "open-ils.search.cat.biblio.tcn",
	argc		=> 3, 
	note		=> "Searches biblio information by search class",
);

sub cat_biblio_search_tcn {

	my( $self, $client, $org_id, $tcn ) = @_;

	$tcn =~ s/.*?(\w+)\s*$/$1/o;
	warn "Searching TCN $tcn\n";

	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	my $request = $session->request( 
			"open-ils.storage.biblio.record_entry.search.tcn_value", $tcn );
	my $response = $request->recv();


	unless ($response) { return []; }

	if($response->isa("OpenSRF::EX")) {
		throw $response ($response->stringify);
	}

	my $record_entry = $response->content;
	my @ids;
	for my $record (@$record_entry) {
		push @ids, $record->id;
	}


	my $record_list = _records_to_mods( @ids );

	for my $rec (@$record_list) {
		$client->respond($rec);
	}
#return _records_to_mods( @ids );


	return undef;

}

__PACKAGE__->register_method(
	method	=> "cat_biblio_search_class",
	api_name	=> "open-ils.search.cat.biblio.class",
	argc		=> 3, 
	note		=> "Searches biblio information by search class",
);

sub cat_biblio_search_class {

	my( $self, $client, $org_id, $class, $sort, $string ) = @_;

	throw OpenSRF::EX::InvalidArg 
		("Not enough args to open-ils.search.cat.biblio.class")
			unless( defined($org_id) and $class and $sort and $string );


	my $search_hash;

	my $method = $self->method_lookup("open-ils.search.biblio.marc");
	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Can't lookup method 'open-ils.search.biblio.marc'");
	}

	my ($records) = $method->run( $cat_search_hash->{$class}, $string );

	my @ids;
	for my $i (@$records) { push @ids, $i->[0]; }

	my $mods_list = _records_to_mods( @ids );

	# ---------------------------------------------------------------
	# append copy count information to the mods objects
	my $session = OpenSRF::AppSession->create("open-ils.storage");

	my $request = $session->request(
		"open-ils.storage.biblio.record_copy_count.batch",  $org_id, @ids );

	for my $id (@ids) {

		warn "receiving copy counts for doc $id\n";

		my $response = $request->recv();
		next unless $response;

		if( $response and UNIVERSAL::isa($response, "Error")) {
			throw $response ($response->stringify);
		}

		my $count = $response->content;
		my $mods_obj = undef;
		for my $m (@$mods_list) {
			$mods_obj = $m if ($m->{doc_id} == $id)
		}
		if($mods_obj) {
			$mods_obj->{copy_count} = $count;
		}

		$client->respond( $mods_obj );

	}	
	$request->finish();

	$session->finish();
	$session->disconnect();
	$session->kill_me();
	# ---------------------------------------------------------------

#	return $mods_list;

	return undef;

}


__PACKAGE__->register_method(
	method	=> "cat_biblio_search_class_stream",
	api_name	=> "open-ils.search.cat.biblio.class.stream",
	argc		=> 3, 
	note		=> "Searches biblio information by search class",
);

sub cat_biblio_search_class_stream {

	my( $self, $client, $org_id, $class, $sort, $string ) = @_;

	throw OpenSRF::EX::InvalidArg 
		("Not enough args to open-ils.search.cat.biblio.class")
			unless( defined($org_id) and $class and $sort and $string );


	my $search_hash;

	my $method = $self->method_lookup("open-ils.search.biblio.marc");
	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Can't lookup method 'open-ils.search.biblio.marc'");
	}

	my ($records) = $method->run( $cat_search_hash->{$class}, $string );

	my @ids;
	for my $i (@$records) { push @ids, $i->[0]; }

	my $mods_list = _records_to_mods( @ids );

	# ---------------------------------------------------------------
	# append copy count information to the mods objects
	my $session = OpenSRF::AppSession->create("open-ils.storage");

	my $request = $session->request(
		"open-ils.storage.biblio.record_copy_count.batch",  $org_id, @ids );

	for my $id (@ids) {

		warn "receiving copy counts for doc $id\n";

		my $response = $request->recv();
		next unless $response;

		if( $response and UNIVERSAL::isa($response, "Error")) {
			throw $response ($response->stringify);
		}

		my $count = $response->content;
		my $mods_obj = undef;
		for my $m (@$mods_list) {
			$mods_obj = $m if ($m->{doc_id} == $id)
		}
		if($mods_obj) {
			$mods_obj->{copy_count} = $count;
		}

		$client->respond( $mods_obj );

	}	
	$request->finish();

	$session->finish();
	$session->disconnect();
	$session->kill_me();
	# ---------------------------------------------------------------

}


__PACKAGE__->register_method(
	method	=> "biblio_search_marc",
	api_name	=> "open-ils.search.biblio.marc",
	argc		=> 1, 
	note		=> "Searches biblio information by marc tag",
);

sub biblio_search_marc {

	my( $self, $client, $search_hash, $string ) = @_;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $request = $session->request( 
			"open-ils.storage.metabib.full_rec.search_fts.index_vector", $search_hash, $string );

	my $response = $request->recv();
	if($response and $response->isa("OpenSRF::EX")) {
		throw $response ($response->stringify);
	}

	my $data = $response->content;

	$request->finish();
	$session->finish();
	$session->disconnect();
	$session->kill_me();

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
=head asdf
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

		$session->disconnect();
		$session->kill_me();

		return $home_ou;
	}

	return OpenILS::Application::AppUtils->get_org_tree();
}



__PACKAGE__->register_method(
	method	=> "copy_count_by_org_unit",
	api_name	=> "open-ils.search.copy_count_by_location",
	argc		=> 1, 
	note		=> "Searches biblio information by marc tag",
);

sub copy_count_by_org_unit {
	my( $self, $client, $org_id, @record_ids ) = @_;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $request = $session->request(
		"open-ils.storage.biblio.record_copy_count.batch",  $org_id, @record_ids );

	for my $id (@record_ids) {

		my $response = $request->recv();
		next unless $response;

		if( $response and UNIVERSAL::isa($response, "Error")) {
			throw $response ($response->stringify);
		}

		my $count = $response->content;
		$client->respond( { record => $id, count => $count } );
	}

	$request->finish();
	$session->disconnect();
	$session->kill_me();
	return undef;
}








# ---------------------------------------------------------------------------
# takes a list of record id's and turns the docs into friendly 
# mods structures.
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
			my $u = OpenILS::Application::Cat::Utils->new();
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
		my $u = OpenILS::Application::Cat::Utils->new();
		$u->start_mods_batch( $last_content->marc );
		my $mods = $u->finish_mods_batch();
		$mods->{doc_id} = $last_content->id();
		push @results, $mods;
	}

	$request->finish();
	$session->finish();
	$session->disconnect();
	$session->kill_me();

	return \@results;

}




1;
