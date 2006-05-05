package OpenILS::Application::Search::Biblio;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenILS::EX;

use JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Editor;

use OpenSRF::Utils::Logger qw/:logger/;


use JSON;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use Digest::MD5 qw(md5_hex);

use XML::LibXML;
use XML::LibXSLT;

use Data::Dumper;
$Data::Dumper::Indent = 0;

use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;


# useful for MARC based searches
my $cat_search_hash =  {
	isbn	=> [ { tag => '020', subfield => 'a' }, ],
	issn	=> [ { tag => '022', subfield => 'a' }, ],
};




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
			"open-ils.storage.direct.biblio.record_entry.batch.retrieve",  @ids );

	while( my $resp = $request->recv ) {
		my $content = $resp->content;
		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch( $content->marc );
		my $mods = $u->finish_mods_batch();
		$mods->doc_id($content->id());
		$mods->tcn($content->tcn_value);
		push @results, $mods;
	}

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
	$mods_obj->copy_count($count);

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
	return undef unless defined $id;

	if(ref($id) and ref($id) == 'ARRAY') {
		return _records_to_mods( @$id );
	}
	my $mods_list = _records_to_mods( $id );
	my $mods_obj = $mods_list->[0];
	return $mods_obj;
}


# Returns the number of copies attached to a record based on org location
__PACKAGE__->register_method(
	method	=> "record_id_to_copy_count",
	api_name	=> "open-ils.search.biblio.record.copy_count",
);

__PACKAGE__->register_method(
	method	=> "record_id_to_copy_count",
	api_name	=> "open-ils.search.biblio.metarecord.copy_count",
);

__PACKAGE__->register_method(
	method	=> "record_id_to_copy_count",
	api_name	=> "open-ils.search.biblio.metarecord.copy_count.staff",
);
sub record_id_to_copy_count {
	my( $self, $client, $org_id, $record_id, $format ) = @_;

	$format = undef if ($format eq 'all');

	my $method = "open-ils.storage.biblio.record_entry.copy_count.atomic";
	my $key = "record";
	if($self->api_name =~ /metarecord/) {
		$method = "open-ils.storage.metabib.metarecord.copy_count.atomic";
		$key = "metarecord";
	}

	if($self->api_name =~ /staff/ ) {
		$method =~ s/atomic/staff\.atomic/og;
		warn "Doing staff search $method\n";
	}


	my $session = OpenSRF::AppSession->create("open-ils.storage");
	warn "copy_count retrieve $record_id\n";
	return undef unless(defined $record_id);

	my $request = $session->request(
		$method, org_unit => $org_id => $key => $record_id, format => $format );


	my $count = $request->gather(1);
	$session->disconnect();
	return [ sort { $a->{depth} <=> $b->{depth} } @$count ];

}




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
			"open-ils.storage.direct.biblio.record_entry.search_where.atomic", 
			{ tcn_value => $tcn, deleted => 'f' } );
			#"open-ils.storage.direct.biblio.record_entry.search.tcn_value.atomic", $tcn );
	my $record_entry = $request->gather(1);

	my @ids;
	for my $record (@$record_entry) {
		push @ids, $record->id;
	}

	$session->disconnect();

	my $size = @ids;
	return { count => $size, ids => \@ids };
}


# --------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "biblio_barcode_to_copy",
	api_name	=> "open-ils.search.asset.copy.find_by_barcode",);
sub biblio_barcode_to_copy { 
	my( $self, $client, $barcode ) = @_;
	my( $copy, $evt ) = $U->fetch_copy_by_barcode($barcode);
	return $evt if $evt;
	return $copy;
}

__PACKAGE__->register_method(
	method	=> "biblio_id_to_copy",
	api_name	=> "open-ils.search.asset.copy.batch.retrieve",);
sub biblio_id_to_copy { 
	my( $self, $client, $ids ) = @_;
	$logger->info("Fetching copies @$ids");
	return $U->storagereq(
		"open-ils.storage.direct.asset.copy.batch.retrieve.atomic", @$ids );
}


__PACKAGE__->register_method(
	method	=> "copy_retrieve", 
	api_name	=> "open-ils.search.asset.copy.retrieve",);
sub copy_retrieve {
	my( $self, $client, $cid ) = @_;
	my( $copy, $evt ) = $U->fetch_copy($cid);
	return $evt if $evt;
	return $copy;
}


# XXX add last 3 circs and total circ count
__PACKAGE__->register_method(
	method	=> "fleshed_copy_retrieve_batch",
	api_name	=> "open-ils.search.asset.copy.fleshed.batch.retrieve");

sub fleshed_copy_retrieve_batch { 
	my( $self, $client, $ids ) = @_;
	$logger->info("Fetching fleshed copies @$ids");
	return $U->storagereq(
		"open-ils.storage.fleshed.asset.copy.batch.retrieve.atomic", @$ids );
}


__PACKAGE__->register_method(
	method	=> "fleshed_copy_retrieve",
	api_name	=> "open-ils.search.asset.copy.fleshed.retrieve",);

sub fleshed_copy_retrieve { 
	my( $self, $client, $id ) = @_;
	my( $c, $e) = $U->fetch_fleshed_copy($id);
	return $e if $e;
	return $c;
}



__PACKAGE__->register_method(
	method	=> "biblio_barcode_to_title",
	api_name	=> "open-ils.search.biblio.find_by_barcode",
);

sub biblio_barcode_to_title {
	my( $self, $client, $barcode ) = @_;

	my $title = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.biblio.record_entry.retrieve_by_barcode", $barcode );

	return { ids => [ $title->id ], count => 1 } if $title;
	return { count => 0 };
}


__PACKAGE__->register_method(
	method	=> "biblio_copy_to_mods",
	api_name	=> "open-ils.search.biblio.copy.mods.retrieve",
);

# takes a copy object and returns it fleshed mods object
sub biblio_copy_to_mods {
	my( $self, $client, $copy ) = @_;

	my $volume = $U->storagereq( 
		"open-ils.storage.direct.asset.call_number.retrieve",
		$copy->call_number() );

	my $mods = _records_to_mods($volume->record());
	$mods = shift @$mods;
	$volume->copies([$copy]);
	push @{$mods->call_numbers()}, $volume;

	return $mods;
}


# ----------------------------------------------------------------------------
# These are the main OPAC search methods
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method		=> 'the_quest_for_knowledge',
	api_name		=> 'open-ils.search.biblio.multiclass',
	signature	=> q/
		Performs a multi class bilbli or metabib search
		@param searchhash A search object layed out like so:
			searches : { "$class" : "$value", ...}
			org_unit : The org id to focus the search at
			depth		: The org depth
			limit		: The search limit
			offset	: The search offset
			format	: The MARC format
			sort		: What field to sort the results on [ author | title | pubdate ]
			sort_dir	: What direction do we sort? [ asc | desc ]
		@return An object of the form 
			{ "count" : $count, "ids" : [ [ $id, $relevancy, $total ], ...] }
	/
);

__PACKAGE__->register_method(
	method		=> 'the_quest_for_knowledge',
	api_name		=> 'open-ils.search.record.multiclass.staff',
	signature	=> q/@see open-ils.search.biblio.multiclass/);
__PACKAGE__->register_method(
	method		=> 'the_quest_for_knowledge',
	api_name		=> 'open-ils.search.metabib.multiclass',
	signature	=> q/@see open-ils.search.biblio.multiclass/);
__PACKAGE__->register_method(
	method		=> 'the_quest_for_knowledge',
	api_name		=> 'open-ils.search.metabib.multiclass.staff',
	signature	=> q/@see open-ils.search.biblio.multiclass/);


sub the_quest_for_knowledge {
	my( $self, $conn, $searchhash ) = @_;

	my $method = 'open-ils.storage.biblio.multiclass.search_fts';
	my $ismeta = 0;
	my @recs;

	if($self->api_name =~ /metabib/) {
		$ismeta = 1;
		$method =~ s/biblio/metabib/o;
	}

	$method .= ".staff" if($self->api_name =~ /staff/);
	$method .= ".atomic";

	for (keys %$searchhash) { 
		delete $$searchhash{$_} unless defined $$searchhash{$_}; }

	my $result = $U->storagereq( $method, %$searchhash );

	return {count => 0} unless ($result && $$result[0]);

	for my $r (@$result) { push(@recs, $r) if ($r and $$r[0]); }
	return { ids => \@recs, 
		count => ($ismeta) ? $result->[0]->[3] : $result->[0]->[2] };
}





# XXX XXX old class search...
=head old search method
__PACKAGE__->register_method(
	method		=> "record_search_class",
	api_name		=> "open-ils.search.biblio.record.class.search",
	signature	=> q/
		Performs a class search for biblio records (not metarecords)
		@param class The search class to use
		@param args A hash of named parameters including:
			term		: The search string,
			org_unit : The org id to focus the search at
			depth		: The org depth
			limit		: The search limit
			offset	: The search offset
			format	: The MARC format
			sort		: What field to sort the results on [ author | title | pubdate ]
			sort_dir	: What direction do we sort? [ asc | desc ]
		The only required argument is the term.
		@return 
	/);

__PACKAGE__->register_method(
	method		=> "record_search_class",
	api_name		=> "open-ils.search.biblio.record.class.search.staff",
	signature	=> q/@see open-ils.search.biblio.record.class.search/);
__PACKAGE__->register_method(
	method	=> "record_search_class",
	api_name	=> "open-ils.search.biblio.metabib.class.search",
	signature	=> q/@see open-ils.search.biblio.record.class.search/);
__PACKAGE__->register_method(
	method	=> "record_search_class",
	api_name	=> "open-ils.search.biblio.metabib.class.search.staff",
	signature	=> q/@see open-ils.search.biblio.record.class.search/);

sub record_search_class {
	my( $self, $client, $class, $args ) = @_;

	my $type		= ($self->api_name =~ /metabib/) ? 1 : 0;
	my $method	= "open-ils.storage.metabib.$class.post_filter.search_fts.metarecord.atomic";
	$method		= "open-ils.storage.biblio.$class.search_fts.record.atomic" unless $type;

	if(!$$args{'sort'}) {
		delete $$args{'sort'}; 
		delete $$args{'sort_dir'};
	}
	$$args{limit}	= 200 if (!$$args{limit} || $$args{limit} > 1000);
	$$args{offset} ||= 0;

	$logger->info("Class search with args: ".Dumper($args));

	$method =~ s/\.atomic/.staff.atomic/o if $self->api_name =~ /staff/o;
	my $result = $U->storagereq( $method, %$args );

	if($result and $result->[0]) {
		my $recs = [];
		for my $r (@$result) { push(@$recs, $r) if ($r and $r->[0]); }
		return { ids => $recs, 
			count => ($type) ? $result->[0]->[3] : $result->[0]->[2] };
	}
	return { count => 0 };
}
=cut




__PACKAGE__->register_method(
	method	=> "biblio_mrid_to_modsbatch_batch",
	api_name	=> "open-ils.search.biblio.metarecord.mods_slim.batch.retrieve");

sub biblio_mrid_to_modsbatch_batch {
	my( $self, $client, $mrids) = @_;
	warn "Performing mrid_to_modsbatch_batch...";
	my @mods;
	my $method = $self->method_lookup("open-ils.search.biblio.metarecord.mods_slim.retrieve");
	for my $id (@$mrids) {
		next unless defined $id;
		my ($m) = $method->run($id);
		push @mods, $m;
	}
	return \@mods;
}


__PACKAGE__->register_method(
	method	=> "biblio_mrid_to_modsbatch",
	api_name	=> "open-ils.search.biblio.metarecord.mods_slim.retrieve",
	notes		=> <<"	NOTES");
	Returns the mvr associated with a given metarecod. If none exists, 
	it is created.
	NOTES

__PACKAGE__->register_method(
	method	=> "biblio_mrid_to_modsbatch",
	api_name	=> "open-ils.search.biblio.metarecord.mods_slim.retrieve.staff",
	notes		=> <<"	NOTES");
	Returns the mvr associated with a given metarecod. If none exists, 
	it is created.
	NOTES

sub biblio_mrid_to_modsbatch {
	my( $self, $client, $mrid ) = @_;

	warn "Grabbing mvr for $mrid\n";

	my $mr = _grab_metarecord($mrid);
	return undef unless $mr;

	if( my $m = $self->biblio_mrid_check_mvr($client, $mr)) {
		return $m;
	}

	return $self->biblio_mrid_make_modsbatch( $client, $mr ); 
}

# converts a metarecord to an mvr
sub _mr_to_mvr {
	my $mr = shift;
	my $perl = JSON->JSON2perl($mr->mods());
	return Fieldmapper::metabib::virtual_record->new($perl);
}

# checks to see if a metarecord has mods, if so returns true;

__PACKAGE__->register_method(
	method	=> "biblio_mrid_check_mvr",
	api_name	=> "open-ils.search.biblio.metarecord.mods_slim.check",
	notes		=> <<"	NOTES");
	Takes a metarecord ID or a metarecord object and returns true
	if the metarecord already has an mvr associated with it.
	NOTES

sub biblio_mrid_check_mvr {
	my( $self, $client, $mrid ) = @_;
	my $mr; 

	if(ref($mrid)) { $mr = $mrid; } 
	else { $mr = _grab_metarecord($mrid); }

	warn "Checking mvr for mr " . $mr->id . "\n";

	return _mr_to_mvr($mr) if $mr->mods();
	return undef;
}

sub _grab_metarecord {

	my $mrid = shift;
	warn "Grabbing MR $mrid\n";

	my $mr = OpenILS::Application::AppUtils->simple_scalar_request( 
		"open-ils.storage", 
		"open-ils.storage.direct.metabib.metarecord.retrieve", $mrid );

	if(!$mr) {
		throw OpenSRF::EX::ERROR 
			("No metarecord exists with the given id: $mrid");
	}

	return $mr;
}

__PACKAGE__->register_method(
	method	=> "biblio_mrid_make_modsbatch",
	api_name	=> "open-ils.search.biblio.metarecord.mods_slim.create",
	notes		=> <<"	NOTES");
	Takes either a metarecord ID or a metarecord object.
	Forces the creations of an mvr for the given metarecord.
	The created mvr is returned.
	NOTES

sub biblio_mrid_make_modsbatch {

	my( $self, $client, $mrid ) = @_;

	my $mr; 
	if(ref($mrid)) { $mr = $mrid; }
	else { $mr = _grab_metarecord($mrid); }
	$mrid = $mr->id;

	warn "Forcing mvr creation for mr " . $mr->id . "\n";
	my $master_id = $mr->master_record;

	my $session = OpenSRF::AppSession->create("open-ils.storage");

	# grab the records attached to this metarecod 
	warn "Creating mods batch for metarecord $mrid\n";
	my $meth = "open-ils.search.biblio.metarecord_to_records.staff";
	$meth = $self->method_lookup($meth);
	my ($id_hash) = $meth->run($mrid);
	my @ids = @{$id_hash->{ids}};
	if(@ids < 1) { return undef; }

	warn "Master ID is $master_id\n";
	# grab the master record to start the mods batch 

	$meth = "open-ils.storage.direct.biblio.record_entry.retrieve";

	my $record = $session->request(
			"open-ils.storage.direct.biblio.record_entry.retrieve", $master_id );
	$record = $record->gather(1);

	#my $record = OpenILS::Application::AppUtils->simple_scalar_request( "open-ils.storage", 

	if(!$record) {
		warn "No record returned with id $master_id";
		throw OpenSRF::EX::ERROR 
	}

	my $u = OpenILS::Utils::ModsParser->new();
	$u->start_mods_batch( $record->marc );
	my $main_doc_id = $record->id();

	@ids = grep { $_ ne $master_id } @ids;

	# now we have to collect all of the marc objects and push them into a mods batch
	my $request = $session->request(
		"open-ils.storage.direct.biblio.record_entry.batch.retrieve",  @ids );

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
	$mods->doc_id($mrid);
	$request->finish();

	$client->respond_complete($mods);

	my $mods_string = JSON->perl2JSON($mods->decast);

	$mr->mods($mods_string);

	my $req = $session->request( 
		"open-ils.storage.direct.metabib.metarecord.update", $mr );


	$req->gather(1);
	$session->finish();
	$session->disconnect();

	return undef;
}



# converts a mr id into a list of record ids

__PACKAGE__->register_method(
	method	=> "biblio_mrid_to_record_ids",
	api_name	=> "open-ils.search.biblio.metarecord_to_records",
);

__PACKAGE__->register_method(
	method	=> "biblio_mrid_to_record_ids",
	api_name	=> "open-ils.search.biblio.metarecord_to_records.staff",
);

sub biblio_mrid_to_record_ids {
	my( $self, $client, $mrid, $args ) = @_;

	my $format	= $$args{format};
	my $org		= $$args{org};
	my $depth	= $$args{depth};

	my $method = "open-ils.storage.ordered.metabib.metarecord.records.atomic";
	$method =~ s/atomic/staff\.atomic/o if $self->api_name =~ /staff/o; 
	my $recs = $U->storagereq($method, $mrid, $format, $org, $depth);

	return { count => scalar(@$recs), ids => $recs };
}


__PACKAGE__->register_method(
	method	=> "biblio_record_to_marc_html",
	api_name	=> "open-ils.search.biblio.record.html" );

my $parser		= XML::LibXML->new();
my $xslt			= XML::LibXSLT->new();
my $marc_sheet;

my $settings_client = OpenSRF::Utils::SettingsClient->new();
sub biblio_record_to_marc_html {
	my( $self, $client, $recordid ) = @_;

	if( !$marc_sheet ) {
		my $dir = $settings_client->config_value( "dirs", "xsl" );
		my $xsl = $settings_client->config_value(
			"apps", "open-ils.search", "app_settings", "marc_html_xsl" );

		$xsl = $parser->parse_file("$dir/$xsl");
		$marc_sheet = $xslt->parse_stylesheet( $xsl );
	}


	my $record = $apputils->simple_scalar_request(
		"open-ils.storage", 
		"open-ils.storage.direct.biblio.record_entry.retrieve",
		$recordid );

	my $xmldoc = $parser->parse_string($record->marc);
	my $html = $marc_sheet->transform($xmldoc);
	$html = $html->toString();
	return $html;

}


=head duplicate
__PACKAGE__->register_method(
	method	=> "retrieve_all_copy_locations",
	api_name	=> "open-ils.search.config.copy_location.retrieve.all" );

my $shelving_locations;
sub retrieve_all_copy_locations {
	my( $self, $client ) = @_;
	if(!$shelving_locations) {
		$shelving_locations = $apputils->simple_scalar_request(
			"open-ils.storage", 
			"open-ils.storage.direct.asset.copy_location.retrieve.all.atomic");
	}
	return $shelving_locations;
}
=cut



__PACKAGE__->register_method(
	method	=> "retrieve_all_copy_statuses",
	api_name	=> "open-ils.search.config.copy_status.retrieve.all" );

my $copy_statuses;
sub retrieve_all_copy_statuses {
	my( $self, $client ) = @_;
	if(!$copy_statuses) {
		$copy_statuses = $apputils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.config.copy_status.retrieve.all.atomic" );
	}
	return $copy_statuses;
}


__PACKAGE__->register_method(
	method	=> "copy_counts_per_org",
	api_name	=> "open-ils.search.biblio.copy_counts.retrieve");

__PACKAGE__->register_method(
	method	=> "copy_counts_per_org",
	api_name	=> "open-ils.search.biblio.copy_counts.retrieve.staff");

sub copy_counts_per_org {
	my( $self, $client, $record_id ) = @_;

	warn "Retreiveing copy copy counts for record $record_id and method " . $self->api_name . "\n";

	my $method = "open-ils.storage.biblio.record_entry.global_copy_count.atomic";
	if($self->api_name =~ /staff/) { $method =~ s/atomic/staff\.atomic/; }

	my $counts = $apputils->simple_scalar_request(
		"open-ils.storage", $method, $record_id );

	$counts = [ sort {$a->[0] <=> $b->[0]} @$counts ];
	return $counts;
}


__PACKAGE__->register_method(
	method		=> "copy_count_summary",
	api_name	=> "open-ils.search.biblio.copy_counts.summary.retrieve",
	notes 		=> <<"	NOTES");
	returns an array of these:
		[ org_id, callnumber_label, <status1_count>, <status2_cout>,...]
		where statusx is a copy status name.  the statuses are sorted
		by id.
	NOTES

sub copy_count_summary {
	my( $self, $client, $rid ) = @_;
	return $U->storagereq(
		'open-ils.storage.biblio.record_entry.status_copy_count.atomic', $rid );
}



=head
__PACKAGE__->register_method(
	method		=> "multiclass_search",
	api_name	=> "open-ils.search.biblio.multiclass",
	notes 		=> <<"	NOTES");
		Performs a multiclass search
		PARAMS( searchBlob, org_unit, format, limit ) 
		where searchBlob is defined like this:
			{ 
				"title" : { "term" : "water" }, 
				"author" : { "term" : "smith" }, 
				... 
			}
	NOTES

__PACKAGE__->register_method(
	method		=> "multiclass_search",
	api_name	=> "open-ils.search.biblio.multiclass.staff",
	notes 		=> "see open-ils.search.biblio.multiclass" );

sub multiclass_search {
	my( $self, $client, $searchBlob, $orgid, $format, $limit ) = @_;

	$logger->debug("Performing multiclass search with org => $orgid, " .
		"format => $format, limit => $limit, and search blob " . Dumper($searchBlob));

	my $meth = 'open-ils.storage.metabib.post_filter.multiclass.search_fts.metarecord.atomic';
	if($self->api_name =~ /staff/) { $meth =~ s/metarecord\.atomic/metarecord.staff.atomic/; }


	my $records = $apputils->simplereq(
		'open-ils.storage', $meth, 
		 org_unit => $orgid, searches => $searchBlob, format => $format, limit => $limit );

	my $count = 0;
	my $recs = [];

	if( ref($records) and $records->[0] and 
		defined($records->[0]->[3])) { $count = $records->[0]->[3];}

	for my $r (@$records) { push( @$recs, $r ) if ($r and $r->[0]); }

	# records has the form: [ mrid, rank, singleRecord / 0, hitCount ];
	return { ids => $recs, count => $count };
}
=cut


=head comment-1
__PACKAGE__->register_method(
	method		=> "multiclass_search",
	api_name		=> "open-ils.search.biblio.multiclass",
	signature	=> q/
		Performs a multiclass search
		@param args A names hash of arguments:
			org_unit : The org to focus the search on
			depth		: The search depth
			format	: Item format
			limit		: Return limit
			offset	: Search offset
			searches : A named hash of searches which has the following format:
				{ 
					"title" : { "term" : "water" }, 
					"author" : { "term" : "smith" }, 
					... 
				}
		@return { ids : <array of ids>, count : hitcount }
	/
);

__PACKAGE__->register_method(
	method		=> "multiclass_search",
	api_name		=> "open-ils.search.biblio.multiclass.staff",
	notes 		=> q/@see open-ils.search.biblio.multiclass/ );

sub multiclass_search {
	my( $self, $client, $args ) = @_;

	$logger->debug("Performing multiclass search with args:\n" . Dumper($args));
	my $meth = 'open-ils.storage.metabib.post_filter.multiclass.search_fts.metarecord.atomic';
	if($self->api_name =~ /staff/) { $meth =~ s/metarecord\.atomic/metarecord.staff.atomic/; }

	my $records = $apputils->simplereq( 'open-ils.storage', $meth, %$args );

	my $count = 0;
	my $recs = [];

	if( ref($records) and $records->[0] and 
		defined($records->[0]->[3])) { $count = $records->[0]->[3];}

	for my $r (@$records) { push( @$recs, $r ) if ($r and $r->[0]); }

	return { ids => $recs, count => $count };
}

=cut



__PACKAGE__->register_method(
	method		=> "marc_search",
	api_name	=> "open-ils.search.biblio.marc",
	notes 		=> <<"	NOTES");
		Example:
		open-ils.storage.biblio.full_rec.multi_search.atomic 
		{ "searches": [{"term":"harry","restrict": [{"tag":245,"subfield":"a"}]}], "org_unit": 1,
        "limit":5,"sort":"author","item_type":"g"}
	NOTES

sub marc_search {
	my( $self, $conn, $args ) = @_;
	my $records = $U->storagereq(
		'open-ils.storage.biblio.full_rec.multi_search.atomic', %$args );

	my $count = 0;

	$count = $records->[0]->[2] if( ref($records) and 
		$records->[0] and defined($records->[0]->[2]));

	return { ids => $records, count => $count };
}



__PACKAGE__->register_method(
	method	=> "biblio_search_isbn",
	api_name	=> "open-ils.search.biblio.isbn",
);

sub biblio_search_isbn { 
	my( $self, $client, $isbn ) = @_;

	$logger->debug("Searching ISBN $isbn");

	my $method = $self->method_lookup("open-ils.search.biblio.marc");

	my ($records) = $method->run(  
		[ {	term => $isbn,
				restrict => $cat_search_hash->{isbn} } ], 1);

	return $records;
}


__PACKAGE__->register_method(
	method	=> "biblio_search_issn",
	api_name	=> "open-ils.search.biblio.issn",
);

sub biblio_search_issn { 
	my( $self, $client, $issn ) = @_;

	$logger->debug("Searching ISSN $issn");

	my $method = $self->method_lookup("open-ils.search.biblio.marc");

	my ($records) = $method->run(  
		[ {	term => $issn,
				restrict => $cat_search_hash->{issn} } ], 1);

	return $records;
}




__PACKAGE__->register_method(
	method	=> "fetch_mods_by_copy",
	api_name	=> "open-ils.search.biblio.mods_from_copy",
);

sub fetch_mods_by_copy {
	my( $self, $client, $copyid ) = @_;
	my ($record, $evt) = $apputils->fetch_record_by_copy( $copyid );
	return $evt if $evt;
	return OpenILS::Event->new('ITEM_NOT_CATALOGED') unless $record->marc;
	return $apputils->record_to_mvr($record);
}





# -------------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "cn_browse",
	api_name	=> "open-ils.search.callnumber.browse.target",
	notes		=> "Starts a callnumber browse"
	);

__PACKAGE__->register_method(
	method	=> "cn_browse",
	api_name	=> "open-ils.search.callnumber.browse.page_up",
	notes		=> "Returns the previous page of callnumbers", 
	);

__PACKAGE__->register_method(
	method	=> "cn_browse",
	api_name	=> "open-ils.search.callnumber.browse.page_down",
	notes		=> "Returns the next page of callnumbers", 
	);


# RETURNS array of arrays like so: label, owning_lib, record, id
sub cn_browse {
	my( $self, $client, @params ) = @_;
	my $method;

	$method = 'open-ils.storage.asset.call_number.browse.target.atomic' 
		if( $self->api_name =~ /target/ );
	$method = 'open-ils.storage.asset.call_number.browse.page_up.atomic'
		if( $self->api_name =~ /page_up/ );
	$method = 'open-ils.storage.asset.call_number.browse.page_down.atomic'
		if( $self->api_name =~ /page_down/ );

	return $apputils->simplereq( 'open-ils.storage', $method, @params );
}
# -------------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => "fetch_cn",
	api_name => "open-ils.search.callnumber.retrieve",
	notes		=> "retrieves a callnumber based on ID",
	);

sub fetch_cn {
	my( $self, $client, $id ) = @_;
	my( $cn, $evt ) = $apputils->fetch_callnumber( $id );
	return $evt if $evt;
	return $cn;
}

__PACKAGE__->register_method (
	method		=> "fetch_copy_by_cn",
	api_name		=> 'open-ils.search.copies_by_call_number.retrieve',
	signature	=> q/
		Returns an array of copy id's by callnumber id
		@param cnid The callnumber id
		@return An array of copy ids
	/
);

sub fetch_copy_by_cn {
	my( $self, $conn, $cnid ) = @_;
	return $U->storagereq(
		'open-ils.storage.id_list.asset.copy.search_where.atomic', 
		{ call_number => $cnid, deleted => 'f' } );
}

__PACKAGE__->register_method (
	method		=> 'fetch_cn_by_info',
	api_name		=> 'open-ils.search.call_number.retrieve_by_info',
	signature	=> q/
		@param label The callnumber label
		@param record The record the cn is attached to
		@param org The owning library of the cn
		@return The callnumber object
	/
);


sub fetch_cn_by_info {
	my( $self, $conn, $label, $record, $org ) = @_;
	return $U->storagereq(
		'open-ils.storage.direct.asset.call_number.search_where',
		{ label => $label, record => $record, owning_lib => $org, deleted => 'f' });
}


		


__PACKAGE__->register_method (
	method => 'bib_extras',
	api_name => 'open-ils.search.biblio.lit_form_map.retrieve.all');
__PACKAGE__->register_method (
	method => 'bib_extras',
	api_name => 'open-ils.search.biblio.item_form_map.retrieve.all');
__PACKAGE__->register_method (
	method => 'bib_extras',
	api_name => 'open-ils.search.biblio.item_type_map.retrieve.all');
__PACKAGE__->register_method (
	method => 'bib_extras',
	api_name => 'open-ils.search.biblio.audience_map.retrieve.all');

sub bib_extras {
	my $self = shift;
	
	return $U->storagereq(
		'open-ils.storage.direct.config.lit_form_map.retrieve.all.atomic')
			if( $self->api_name =~ /lit_form/ );

	return $U->storagereq(
		'open-ils.storage.direct.config.item_form_map.retrieve.all.atomic')
			if( $self->api_name =~ /item_form_map/ );

	return $U->storagereq(
		'open-ils.storage.direct.config.item_type_map.retrieve.all.atomic')
			if( $self->api_name =~ /item_type_map/ );

	return $U->storagereq(
		'open-ils.storage.direct.config.audience_map.retrieve.all.atomic')
			if( $self->api_name =~ /audience/ );

	return [];
}



__PACKAGE__->register_method(
	method	=> 'fetch_slim_record',
	api_name	=> 'open-ils.search.biblio.record_entry.slim.retrieve',
	signature=> q/
		Returns a biblio.record_entry without the attached marcxml
	/
);

sub fetch_slim_record {
	my( $self, $conn, $ids ) = @_;

	my $editor = OpenILS::Utils::Editor->new;
	my @res;
	for( @$ids ) {
		return $editor->event unless
			my $r = $editor->retrieve_biblio_record_entry($_);
		$r->clear_marc;
		push(@res, $r);
	}
	return \@res;
}







1;


