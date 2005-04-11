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
			"open-ils.storage.direct.metabib.full_rec.search_fts.index_vector", 
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
			"open-ils.storage.direct.biblio.record_marc.batch.retrieve",  @ids );

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
	warn "Retrieving MODS object for record $id\n";
	return undef unless(defined $id);

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
	warn "copy_count retrieve $record_id\n";
	return undef unless(defined $record_id);

	my $request = $session->request(
		"open-ils.storage.direct.biblio.record_copy_count",  $org_id, $record_id );

	warn "copy_count wait $record_id\n";
	$request->wait_complete;

	warn "copy_count recv $record_id\n";
	my $response = $request->recv();
	return undef unless $response;

	warn "copy_count after recv $record_id\n";

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

	isbn	=> [
		{ tag => "020", subfield => "a" },
	],

};


__PACKAGE__->register_method(
	method	=> "biblio_search_tcn",
	api_name	=> "open-ils.search.biblio.tcn",
	argc		=> 3, 
	note		=> "Retrieve a record by TCN",
);

sub biblio_search_tcn {

	my( $self, $client, $tcn ) = @_;

	$tcn =~ s/.*?(\w+)\s*$/$1/o;
	warn "Searching TCN $tcn\n";

	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	my $request = $session->request( 
			"open-ils.storage.direct.biblio.record_entry.search.tcn_value", $tcn );
	warn "tcn going into recv\n";
	my $response = $request->recv();


	unless ($response) { return []; }

	if(UNIVERSAL::isa($response,"OpenSRF::EX")) {
		warn "Received exception for tcn search\n";
		throw $response ($response->stringify);
	}

	my $record_entry = $response->content;
	my @ids;
	for my $record (@$record_entry) {
		push @ids, $record->id;
	}

	warn "received ID's for tcn search @ids\n";

	my $size = @ids;
	return { count => $size, ids => \@ids };

}


# --------------------------------------------------------------------------------
# ISBN

__PACKAGE__->register_method(
	method	=> "biblio_search_isbn",
	api_name	=> "open-ils.search.biblio.isbn",
);

sub biblio_search_isbn { 
	my( $self, $client, $isbn ) = @_;
	throw OpenSRF::EX::InvalidArg 

		("biblio_search_isbn needs an ISBN to search")
			unless defined $isbn;

	warn "biblio search for ISBN $isbn\n";
	my $method = $self->method_lookup("open-ils.search.biblio.marc");
	my ($records) = $method->run( $cat_search_hash->{isbn}, $isbn );
	my @ids;
	for my $i (@$records) { 
		if( ref($i) and defined($i->[0])) { 
			push @ids, $i->[0]; 
		}
	}

	my $size = @ids;
	return { count => $size, ids => \@ids };
}

# XXX make me work
__PACKAGE__->register_method(
	method	=> "biblio_search_barcode",
	api_name	=> "open-ils.search.biblio.barcode",
);

sub biblio_search_barcode { 
	my( $self, $client, $barcode ) = @_;
	throw OpenSRF::EX::InvalidArg 

		("biblio_search_barcode needs an ISBN to search")
			unless defined $barcode;

	warn "biblio search for ISBN $barcode\n";
	my $records = OpenILS::Application::AppUtils->simple_scalar_request(
			"open-ils.storage", "open-ils.storage.direct.asset.copy.search.barcode",
			$barcode );

	my @ids;
	for my $i (@$records) { 
		if( ref($i) and defined($i->[0])) { 
			push @ids, $i->[0]; 
		}
	}

	my $size = @ids;
	return { count => $size, ids => \@ids };
}



# --------------------------------------------------------------------------------

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
		"open-ils.storage.direct.biblio.record_copy_count.batch",  $org_id, @ids );

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

	my( $self, $client, $org_id, $class, $string, $limit, $offset ) = @_;

	$offset	||= 0;
	$limit	||= 100;
	$limit -= 1;


	$string = OpenILS::Application::Search->filter_search($string);
	if(!$string) { return undef; }

	warn "Searching cat.biblio.class.id string: $string offset: $offset limit: $limit\n";

	throw OpenSRF::EX::InvalidArg 
		("Not enough args to open-ils.search.cat.biblio.class")
			unless( defined($org_id) and $class and $string );


	my $search_hash;

	my $cache_key = md5_hex( $org_id . $class . $string );
	my $id_array = OpenILS::Application::SearchCache->get_cache($cache_key);

	if(ref($id_array)) {
		warn "Return search from cache\n";
		my $size = @$id_array;
		my @ids = @$id_array[ $offset..($offset+$limit) ];
		warn "Returning cat.biblio.class.id $string\n";
		return { count => $size, ids => \@ids };
	}

	my $method = $self->method_lookup("open-ils.search.biblio.marc");
	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Can't lookup method 'open-ils.search.biblio.marc'");
	}

	my ($records) = $method->run( $cat_search_hash->{$class}, $string );

	my @cache_ids;

	for my $i (@$records) { 
		if(defined($i->[0])) {
			push @cache_ids, $i->[0]; 
		}
	}

	my @ids = @cache_ids[ $offset..($offset+$limit) ];
	my $size = @$records;

	OpenILS::Application::SearchCache->put_cache( 
			$cache_key, \@cache_ids, $size );

	warn "Returning cat.biblio.class.id $string\n";
	return { count =>$size, ids => \@ids };

}


__PACKAGE__->register_method(
	method	=> "biblio_search_class",
	api_name	=> "open-ils.search.biblio.class",
	argc		=> 3, 
	note		=> "Searches biblio information by search class and returns the IDs",
);

sub biblio_search_class {

	my( $self, $client, $class, $string, $org_id, $org_type, $limit, $offset ) = @_;

	$offset		||= 0;
	$limit		= 100 unless defined($limit and $limit > 0 );
	$org_id	 	= "1" unless defined($org_id); # xxx
	$org_type	= 0	unless defined($org_type);


	warn "Searching biblio.class.id string: $string offset: $offset limit: $limit\n";

	$string = OpenILS::Application::Search->filter_search($string);
	if(!$string) { return undef; }

	if( !defined($org_id) or !$class or !$string ) {
		warn "not enbough args to metarecord searcn\n";
		throw OpenSRF::EX::InvalidArg 
			("Not enough args to open-ils.search.cat.biblio.class")
	}

	$class =~ s/\s+//g;

	if( ($class ne "title") and ($class ne "author") and 
		($class ne "subject") and ($class ne "keyword") ) {
		warn "Invalid search class: $class\n";
		throw OpenSRF::EX::InvalidArg ("Not a valid search class: $class")
	}

	# grab the mr id's from storage

	my $method = "open-ils.storage.metabib.$class.search_fts.metarecord_count";
	warn "Performing count method $method\n";
	my $session = OpenSRF::AppSession->create('open-ils.storage');
	my $request = $session->request( $method, $string, $org_id, $org_type );
	my $response = $request->recv();

	if(UNIVERSAL::isa($response, "OpenSRF::EX")) {
		throw $response ($response->stringify);
	}

	my $count = $response->content;
	warn "Received count $count\n";

	# XXX check count size and respond accordingly

	$request->finish();
	warn "performing mr search\n";
	$request = $session->request(	
		"open-ils.storage.metabib.$class.search_fts.metarecord",
		$string, $org_id, $org_type, $limit );

	warn "a\n";
	$response = $request->recv();

	if(UNIVERSAL::isa($response, "OpenSRF::EX")) {
		warn "Recieved Exception from storage: " . $response->stringify . "\n";
		$response->{'msg'} = $response->stringify();
		throw $response ($response->stringify);
	}

	warn "b\n";

	my $records = $response->content;

	my @all_ids;

	for my $i (@$records) { 
		if(defined($i->[0])) {
			push @all_ids, $i->[0]; 
		}
	}

	my @ids = @all_ids[ $offset..($offset+$limit) ];
	@ids = grep { defined($_) } @ids;
	#my $size = @$records;

	$request->finish();
	$session->finish();
	$session->disconnect();

	warn "Returning biblio.class $string\n";
	return { count =>$count, ids => \@ids };

}




__PACKAGE__->register_method(
	method	=> "biblio_mrid_to_modsbatch",
	api_name	=> "open-ils.search.biblio.metarecord.mods_slim.retrieve",
);

sub biblio_mrid_to_modsbatch {
	my( $self, $client, $mrid ) = @_;

	throw OpenSRF::EX::InvalidArg 
		("search.biblio.metarecord_to_mods requires mr id")
			unless defined( $mrid );

	warn "Creating mods batch for metarecord $mrid\n";
	my $id_hash = biblio_mrid_to_record_ids( undef, undef,  $mrid );
	my @ids = @{$id_hash->{ids}};

	if(@ids < 1) { return undef; }

	# grab the master record...

	my $master_id = OpenILS::Application::AppUtils->simple_scalar_request( "open-ils.storage", 
			"open-ils.storage.direct.metabib.metarecord.search.master_record", $mrid );

	$master_id = $master_id->[0]; # there should only be one

	use Data::Dumper;
	warn "Master Record: " . Dumper($master_id);

	if (!ref($master_id) or !defined($master_id->id())) {
		warn "No Master Record Found, using first found id\n";
		$master_id = shift @ids;
	} else {
		$master_id = $master_id->id();
	}

	warn "Master ID is $master_id\n";

	# grab the master record to start the mods batch 

	my $record = OpenILS::Application::AppUtils->simple_scalar_request( "open-ils.storage", 
			"open-ils.storage.direct.biblio.record_marc.retrieve", $master_id );

	if(!$record) {
		throw OpenSRF::EX::ERROR 
			("No record returned with id $master_id");
	}

	my $u = OpenILS::Utils::ModsParser->new();
	$u->start_mods_batch( $record->marc );
	my $main_doc_id = $record->id();

	@ids = grep { $_ ne $master_id } @ids;

	warn "NON-Master IDs are @ids\n";

	# now we have to collect all of the marc objects and push them into a mods batch
	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $request = $session->request(
			"open-ils.storage.direct.biblio.record_marc.batch.retrieve",  @ids );

	while( my $response = $request->recv() ) {

		next unless $response;
		if(UNIVERSAL::isa( $response,"OpenSRF::EX")) {
			throw $response ($response->stringify);
		}

		my $content = $response->content;

		if( $content ) {
			$u->push_mods_batch( $content->marc );
		}
	}

	my $mods = $u->finish_mods_batch();
	$mods->{doc_id} = $main_doc_id;

	$request->finish();
	$session->finish();
	$session->disconnect();

	return $mods;

}



# converts a mr id into a list of record ids

__PACKAGE__->register_method(
	method	=> "biblio_mrid_to_record_ids",
	api_name	=> "open-ils.search.biblio.metarecord_to_records",
);

sub biblio_mrid_to_record_ids {
	my( $self, $client, $mrid ) = @_;

	throw OpenSRF::EX::InvalidArg 
		("search.biblio.metarecord_to_record_ids requires mr id")
			unless defined( $mrid );

	warn "Searching for record for MR $mrid\n";

	my $mrmaps = OpenILS::Application::AppUtils->simple_scalar_request( "open-ils.storage", 
			"open-ils.storage.direct.metabib.metarecord_source_map.search.metarecord", $mrid );

	my @ids;
	for my $map (@$mrmaps) { push @ids, $map->source(); }

	warn "Recovered id's [@ids] for mr $mrid\n";

	my $size = @ids;

	return { count => $size, ids => \@ids };

}



1;
