package OpenILS::Application::Search::StaffClient;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use Digest::MD5 qw(md5_hex);
use OpenILS::Application::Search;

# Searches specific to the staff client code

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
	OpenILS::Application::SearchCache->put_cache( $cache_key, \@cache_ids, $size );

	return { count =>$size, ids => \@ids };

}



1;
