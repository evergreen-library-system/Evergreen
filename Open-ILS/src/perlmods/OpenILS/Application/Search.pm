package OpenILS::Application::Search;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use OpenILS::Utils::Fieldmapper;
use Time::HiRes qw(time);
use OpenILS::Application::Cat::Utils;

use OpenSRF::EX qw(:try);

sub _child_init {

	try {
		OpenSRF::Application->method_lookup( "blah" );

	} catch Error with { 
		warn "Child Init Failed: " . shift() . "\n";
	};

}

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

	my( $self, $client, $tcn ) = @_;

	my $session = OpenSRF::AppSession->create( "open-ils.storage" );
	my $request = $session->request( 
			"open-ils.storage.biblio.record_entry.search.tcn_value", $tcn );
	my $response = $request->recv();


	unless ($response) { return undef; }

	if($response->isa("OpenSRF::EX")) {
		warn $response->stringify();
		throw $response ($response->stringify);
	}


	my $record_entry = $response->content;
	$record_entry = $record_entry->[0];
	$request->finish();

	$request = $session->request(
		"open-ils.storage.biblio.record_marc.retrieve",  $record_entry->id() );
	$response = $request->recv();

	unless ($response) { return undef; }

	if($response->isa("OpenSRF::EX")) {
		warn $response->stringify();
		throw $response ($response->stringify);
	}

	my $marcxml = $response->content;

	my $u = OpenILS::Application::Cat::Utils->new();
	$u->start_mods_batch( $marcxml->marc );
	my $mods = $u->finish_mods_batch();
	$mods->{doc_id} = $marcxml->id();


	$request->finish();
	$session->disconnect;
	$session->kill_me;

	return $mods;
}


__PACKAGE__->register_method(
	method	=> "cat_biblio_search_class",
	api_name	=> "open-ils.search.cat.biblio.class",
	argc		=> 3, 
	note		=> "Searches biblio information by search class",
);

sub cat_biblio_search_class {
	my( $self, $client, $class, $sort, $string ) = @_;

	# sort = title, author, pubdate

	warn "Starting search " . time() . "\n";
	
	my $search_hash;

	warn "Searching $class, $sort, $string\n";
	
	warn "Looking up method: "  . time() . "\n";

	my $method = $self->method_lookup("open-ils.search.biblio.marc");
	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Can't lookup method 'open-ils.search.biblio.marc'");
	}

	warn "Running: "  . time() . "\n";

	my ($records) = $method->run( $cat_search_hash->{$class}, $string );

	my @ids;

	for my $i (@$records) {
		push @ids, $i->[0];
	}

	warn "Found Id's: @ids\n";
	warn "Search For Id's complete, fixing: "  . time() . "\n";

	my @results = ();

	my @marcxml_objs;
	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $request = $session->request(
			"open-ils.storage.biblio.record_marc.batch.retrieve",  @ids );


	my $last_content = undef;

	while( my $response = $request->recv() ) {

		warn "Received record from storage " . time() . "\n";

		if( $last_content ) {
			my $u = OpenILS::Application::Cat::Utils->new();
			$u->start_mods_batch( $last_content->marc );
			my $mods = $u->finish_mods_batch();
			$mods->{doc_id} = $last_content->id();
			warn "Processed mods " . time() . "\n";
			#$client->respond( $mods );
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
		warn "Processed mods " . time() . "\n";
		#$client->respond( $mods );
		push @results, $mods;
	}


	$client->respond( \@results );
	
	$request->finish();
	$session->finish();
	$session->disconnect();
	$session->kill_me();
	
	return undef;

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




1;
