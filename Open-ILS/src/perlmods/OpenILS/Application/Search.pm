package OpenILS::Application::Search;
use base qw/OpenSRF::Application/;
use OpenSRF::EX qw(:try);
use strict; use warnings;
use OpenILS::Utils::Fieldmapper;
use Time::HiRes qw(time);
use OpenILS::Application::Cat::Utils;

sub child_init {

	try {
		OpenSRF::Application->method_lookup( "blah" );

	} catch Error with { 
		warn "Child Init Failed: " . shift() . "\n";
	};

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

	if( $class eq "author" ) {

		$search_hash =  [ 
				{ tag => "100", subfield => "a"} ,
				{ tag => "700", subfield => "a"} ]; 

	} elsif( $class eq "title" ) { 

		$search_hash = [ 
				{ tag => "245", subfield => "a"},
				{ tag => "242", subfield => "a"}, 
				{ tag => "240", subfield => "a"},
				{ tag => "210", subfield => "a"},
		];

	} elsif( $class eq "subject" ) { 

		$search_hash =  [ { tag => "650", subfield => "_" } ];

	} elsif( $class eq "tcn" ) { 

		$search_hash = [	{ tag => "035", subfield => "_" } ];
	}

	
	warn "Looking up method: "  . time() . "\n";

	my $method = $self->method_lookup("open-ils.search.biblio.marc");
	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Can't lookup method 'open-ils.search.biblio.marc'");
	}

	warn "Running: "  . time() . "\n";

	my ($records) = $method->run( $search_hash, $string );

	warn "Search For Id's complete, fixing: "  . time() . "\n";
	

	my @results = ();


	$method = $self->method_lookup("open-ils.storage.biblio.record_marc.batch.retrieve");
	warn "Found method batch " . time() . "\n";

	if(!$method) {
		throw OpenSRF::EX::PANIC ("Can't lookup method 'open-ils.storage.biblio.record_marc.batch.retrieve");
	}

	warn "running batch " . time() . "\n";
	my @marxml_objs = $method->run( @$records );
	warn "done running batch " . time() . "\n";

	my $start = 1;
	for my $marcxml (@marxml_objs) { 
		warn "Starting batch " . time() . "\n";
		my $u = OpenILS::Application::Cat::Utils->new();
		$u->start_mods_batch( $marcxml->marc );
		my $mods = $u->finish_mods_batch();
		push @results, $mods;
	}
	warn "REturning \n";

	use Data::Dumper;
	warn Dumper \@results;


	#@records = sort { $a->{$sort} <=> $b->{$sort} } @records;

	return \@results;

}



__PACKAGE__->register_method(
	method	=> "biblio_search_marc",
	api_name	=> "open-ils.search.biblio.marc",
	argc		=> 1, 
	note		=> "Searches biblio information by marc tag",
);

sub biblio_search_marc {
	my( $self, $client, $search_hash, $string ) = @_;


	warn "Looking up search method: "  . time() . "\n";
	my $method = $self->method_lookup( "open-ils.storage.metabib.full_rec.search.fts" );
	if(!$method) {
		throw OpenSRF::EX::PANIC 
			("Can't lookup method 'open-ils.storage open-ils.storage.metabib.full_rec.search.fts'");
	}

	warn "Running search method: "  . time() . "\n";
	my ($data) = $method->run( $search_hash, $string );
	my @ids;

	for my $i (@$data) {
		push @ids, $i->[0];
	}
	
	warn "returning id's @ids\n";

	return \@ids;

}




1;
