package OpenILS::Application::Search::Biblio;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::SettingsClient;

use OpenILS::Application::AppUtils;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use Digest::MD5 qw(md5_hex);

# Houses biblio search utilites 

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
	my $response = $request->recv(20);

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
	my $cmethod = $self->method_lookup(
			"open-ils.search.biblio.record.copy_count");
	my ($count) = $cmethod->run($org_id, $id);
	$mods_obj->{copy_count} = $count;

	return $mods_obj;
}


__PACKAGE__->register_method(
	method	=> "record_id_to_mods_slim",
	api_name	=> "open-ils.search.biblio.record.mods_slim.retrieve",
	argc		=> 1, 
	note		=> "Provide ID, we provide the mods"
);

# converts a record into a mods object with NO copy counts attached
sub record_id_to_mods_slim {
	my( $self, $client, $id ) = @_;
	my $mods_list = _records_to_mods( $id );
	my $mods_obj = $mods_list->[0];
	return $mods_obj;
}


# Returns the number of copies attached to a record based on org location
__PACKAGE__->register_method(
	method	=> "record_id_to_copy_count",
	api_name	=> "open-ils.search.biblio.record.copy_count",
	argc		=> 2, 
	note		=> "Provide ID, we provide the copy count"
);

sub record_id_to_copy_count {
	my( $self, $client, $org_id, $record_id ) = @_;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	warn "mods retrieve $record_id\n";
	my $request = $session->request(
		"open-ils.storage.biblio.record_copy_count",  $org_id, $record_id );

	warn "mods retrieve wait $record_id\n";
	$request->wait_complete;

	warn "mods retrieve recv $record_id\n";
	my $response = $request->recv();
	return undef unless $response;

	warn "mods retrieve after recv $record_id\n";

	if( $response and UNIVERSAL::isa($response, "Error")) {
		throw $response ($response->stringify);
	}

	my $count = $response->content;

	$request->finish();
	$session->finish();
	$session->disconnect();

	return $count;
}


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
	return undef unless (ref($mods_list) eq "ARRAY");

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

	return undef;
}



__PACKAGE__->register_method(
	method	=> "cat_biblio_search_class_id",
	api_name	=> "open-ils.search.cat.biblio.class.id",
	argc		=> 3, 
	note		=> "Searches biblio information by search class and returns the IDs",
);

sub cat_biblio_search_class_id {

	my( $self, $client, $org_id, $class, $sort, $string ) = @_;

	$string = OpenILS::Application::Search->filter_search($string);
	if(!$string) { return undef; }

	warn "Searching cat.biblio.class.id $string\n";

	throw OpenSRF::EX::InvalidArg 
		("Not enough args to open-ils.search.cat.biblio.class")
			unless( defined($org_id) and $class and $sort and $string );


	my $search_hash;

	my $cache_key = md5_hex( $org_id . $class . $sort . $string );
	my $id_array = OpenILS::Application::SearchCache->get_cache($cache_key);

	if(ref($id_array)) {
		warn "Return search from cache\n";
		my $size = @$id_array;
		my @ids;
		my $x = 0;
		for my $i (@$id_array) {
			if($x++ > 200){last;}
			push @ids, $i;
		}
		warn "Returning cat.biblio.class.id $string\n";
		return { count => $size, ids => \@ids };
	}

	my $method = $self->method_lookup("open-ils.search.biblio.marc");
	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Can't lookup method 'open-ils.search.biblio.marc'");
	}

	my ($records) = $method->run( $cat_search_hash->{$class}, $string );

	my @ids;
	my @cache_ids;

	# add some sanity checking
	my $x=0; # Here we're limiting by 200
	for my $i (@$records) { 
		if($x++ < 200 ){
			push @ids, $i->[0]; 
		}
		push @cache_ids, $i->[0]; 
	}
	my $size = @$records;

	OpenILS::Application::SearchCache->put_cache( 
			$cache_key, \@cache_ids, $size );

	warn "Returning cat.biblio.class.id $string\n";
	return { count =>$size, ids => \@ids };

}



1;
