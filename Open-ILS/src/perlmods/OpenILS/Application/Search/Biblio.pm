package OpenILS::Application::Search::Biblio;
use base qw/OpenILS::Application/;
use strict; use warnings;


use OpenSRF::Utils::JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Cache;
use Encode;

use OpenSRF::Utils::Logger qw/:logger/;


use OpenSRF::Utils::JSON;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use Digest::MD5 qw(md5_hex);

use XML::LibXML;
use XML::LibXSLT;

use Data::Dumper;
$Data::Dumper::Indent = 0;

use OpenILS::Const qw/:const/;

use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;

my $pfx = "open-ils.search_";

my $cache;
my $cache_timeout;
my $superpage_size;
my $max_superpages;

sub initialize {
	$cache = OpenSRF::Utils::Cache->new('global');
	my $sclient = OpenSRF::Utils::SettingsClient->new();
	$cache_timeout = $sclient->config_value(
			"apps", "open-ils.search", "app_settings", "cache_timeout" ) || 300;

	$superpage_size = $sclient->config_value(
			"apps", "open-ils.search", "app_settings", "superpage_size" ) || 500;

	$max_superpages = $sclient->config_value(
			"apps", "open-ils.search", "app_settings", "max_superpages" ) || 20;

	$logger->info("Search cache timeout is $cache_timeout, ".
        " superpage_size is $superpage_size, max_superpages is $max_superpages");
}



# ---------------------------------------------------------------------------
# takes a list of record id's and turns the docs into friendly 
# mods structures. Creates one MODS structure for each doc id.
# ---------------------------------------------------------------------------
sub _records_to_mods {
	my @ids = @_;
	
	my @results;
	my @marcxml_objs;

	my $session = OpenSRF::AppSession->create("open-ils.cstore");
	my $request = $session->request(
			"open-ils.cstore.direct.biblio.record_entry.search", { id => \@ids } );

	while( my $resp = $request->recv ) {
		my $content = $resp->content;
		next if $content->id == OILS_PRECAT_RECORD;
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
    authoritative => 1,
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
	return OpenILS::Event->new('BIBLIO_RECORD_ENTRY_NOT_FOUND') unless $mods_obj;
	return $mods_obj;
}


# Returns the number of copies attached to a record based on org location
__PACKAGE__->register_method(
	method	=> "record_id_to_copy_count",
	api_name	=> "open-ils.search.biblio.record.copy_count",
);

__PACKAGE__->register_method(
	method	=> "record_id_to_copy_count",
    authoritative => 1,
	api_name	=> "open-ils.search.biblio.record.copy_count.staff",
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

	return [] unless $record_id;
	$format = undef if (!$format or $format eq 'all');

	my $method = "open-ils.storage.biblio.record_entry.copy_count.atomic";
	my $key = "record";

	if($self->api_name =~ /metarecord/) {
		$method = "open-ils.storage.metabib.metarecord.copy_count.atomic";
		$key = "metarecord";
	}

	$method =~ s/atomic/staff\.atomic/og if($self->api_name =~ /staff/ );

	my $count = $U->storagereq( $method, 
		org_unit => $org_id, $key => $record_id, format => $format );

	return [ sort { $a->{depth} <=> $b->{depth} } @$count ];
}




__PACKAGE__->register_method(
	method	=> "biblio_search_tcn",
	api_name	=> "open-ils.search.biblio.tcn",
	argc		=> 3, 
	note		=> "Retrieve a record by TCN",
);

sub biblio_search_tcn {

	my( $self, $client, $tcn, $include_deleted ) = @_;

    $tcn =~ s/^\s+|\s+$//og;

	my $e = new_editor();
   my $search = {tcn_value => $tcn};
   $search->{deleted} = 'f' unless $include_deleted;
	my $recs = $e->search_biblio_record_entry( $search, {idlist =>1} );
	
	return { count => scalar(@$recs), ids => $recs };
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
	return $U->cstorereq(
		"open-ils.cstore.direct.asset.copy.search.atomic", { id => $ids } );
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

__PACKAGE__->register_method(
	method	=> "volume_retrieve", 
	api_name	=> "open-ils.search.asset.call_number.retrieve");
sub volume_retrieve {
	my( $self, $client, $vid ) = @_;
	my $e = new_editor();
	my $vol = $e->retrieve_asset_call_number($vid) or return $e->event;
	return $vol;
}

__PACKAGE__->register_method(
	method	=> "fleshed_copy_retrieve_batch",
    authoritative => 1,
	api_name	=> "open-ils.search.asset.copy.fleshed.batch.retrieve");

sub fleshed_copy_retrieve_batch { 
	my( $self, $client, $ids ) = @_;
	$logger->info("Fetching fleshed copies @$ids");
	return $U->cstorereq(
		"open-ils.cstore.direct.asset.copy.search.atomic",
		{ id => $ids },
		{ flesh => 1, 
		  flesh_fields => { acp => [ qw/ circ_lib location status stat_cat_entries / ] }
		});
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
	method => 'fleshed_by_barcode',
	api_name	=> "open-ils.search.asset.copy.fleshed2.find_by_barcode",);
sub fleshed_by_barcode {
	my( $self, $conn, $barcode ) = @_;
	my $e = new_editor();
	my $copyid = $e->search_asset_copy(
		{barcode => $barcode, deleted => 'f'}, {idlist=>1})->[0]
		or return $e->event;
	return fleshed_copy_retrieve2( $self, $conn, $copyid);
}


__PACKAGE__->register_method(
	method	=> "fleshed_copy_retrieve2",
	api_name	=> "open-ils.search.asset.copy.fleshed2.retrieve",);

sub fleshed_copy_retrieve2 { 
	my( $self, $client, $id ) = @_;
	my $e = new_editor();
	my $copy = $e->retrieve_asset_copy(
		[
			$id,
			{ 
				flesh				=> 2,
				flesh_fields	=> { 
					acp => [ qw/ location status stat_cat_entry_copy_maps notes age_protect / ],
					ascecm => [ qw/ stat_cat stat_cat_entry / ],
				}
			}
		]
	) or return $e->event;

	# For backwards compatibility
	#$copy->stat_cat_entries($copy->stat_cat_entry_copy_maps);

	if( $copy->status->id == OILS_COPY_STATUS_CHECKED_OUT ) {
		$copy->circulations(
			$e->search_action_circulation( 
				[	
					{ target_copy => $copy->id },
					{
						order_by => { circ => 'xact_start desc' },
						limit => 1
					}
				]
			)
		);
	}

	return $copy;
}


__PACKAGE__->register_method(
	method => 'flesh_copy_custom',
	api_name => 'open-ils.search.asset.copy.fleshed.custom'
);

sub flesh_copy_custom {
	my( $self, $conn, $copyid, $fields ) = @_;
	my $e = new_editor();
	my $copy = $e->retrieve_asset_copy(
		[
			$copyid,
			{ 
				flesh				=> 1,
				flesh_fields	=> { 
					acp => $fields,
				}
			}
		]
	) or return $e->event;
	return $copy;
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
    method => 'title_id_by_item_barcode',
    api_name => 'open-ils.search.bib_id.by_barcode'
);

sub title_id_by_item_barcode {
    my( $self, $conn, $barcode ) = @_;
    my $e = new_editor();
    my $copies = $e->search_asset_copy(
        [
            { deleted => 'f', barcode => $barcode },
            {
                flesh => 2,
                flesh_fields => {
                    acp => [ 'call_number' ],
                    acn => [ 'record' ]
                }
            }
        ]
    );

    return $e->event unless @$copies;
    return $$copies[0]->call_number->record->id;
}


__PACKAGE__->register_method(
	method	=> "biblio_copy_to_mods",
	api_name	=> "open-ils.search.biblio.copy.mods.retrieve",
);

# takes a copy object and returns it fleshed mods object
sub biblio_copy_to_mods {
	my( $self, $client, $copy ) = @_;

	my $volume = $U->cstorereq( 
		"open-ils.cstore.direct.asset.call_number.retrieve",
		$copy->call_number() );

	my $mods = _records_to_mods($volume->record());
	$mods = shift @$mods;
	$volume->copies([$copy]);
	push @{$mods->call_numbers()}, $volume;

	return $mods;
}


__PACKAGE__->register_method(
    api_name => 'open-ils.search.biblio.multiclass.query',
    method => 'multiclass_query',
    signature => q#
        @param arghash @see open-ils.search.biblio.multiclass
        @param query Raw human-readable query string.  
            Recognized search keys include: 
                keyword/kw - search keyword(s)
                author/au/name - search author(s)
                title/ti - search title
                subject/su - search subject
                series/se - search series
                lang - limit by language (specifiy multiple langs with lang:l1 lang:l2 ...)
                site - search at specified org unit, corresponds to actor.org_unit.shortname
                sort - sort type (title, author, pubdate)
                dir - sort direction (asc, desc)
                available - if set to anything other than "false" or "0", limits to available items

                keyword, title, author, subject, and series support additional search 
                subclasses, specified with a "|". For example, "title|proper:gone with the wind" 
                For more, see config.metabib_field

        @param docache @see open-ils.search.biblio.multiclass
    #
);
__PACKAGE__->register_method(
    api_name => 'open-ils.search.biblio.multiclass.query.staff',
    method => 'multiclass_query',
    signature => '@see open-ils.search.biblio.multiclass.query');
__PACKAGE__->register_method(
    api_name => 'open-ils.search.metabib.multiclass.query',
    method => 'multiclass_query',
    signature => '@see open-ils.search.biblio.multiclass.query');
__PACKAGE__->register_method(
    api_name => 'open-ils.search.metabib.multiclass.query.staff',
    method => 'multiclass_query',
    signature => '@see open-ils.search.biblio.multiclass.query');

sub multiclass_query {
    my($self, $conn, $arghash, $query, $docache) = @_;

    $logger->debug("initial search query => $query");
    my $orig_query = $query;

    $query =~ s/\+/ /go;
    $query =~ s/'/ /go;
    $query =~ s/^\s+//go;

    # convert convenience classes (e.g. kw for keyword) to the full class name
    $query =~ s/kw(:|\|)/keyword$1/go;
    $query =~ s/ti(:|\|)/title$1/go;
    $query =~ s/au(:|\|)/author$1/go;
    $query =~ s/su(:|\|)/subject$1/go;
    $query =~ s/se(:|\|)/series$1/go;
    $query =~ s/name(:|\|)/author$1/og;

    $logger->debug("cleansed query string => $query");
    my $search = $arghash->{searches} = {};

    while ($query =~ s/((?:keyword(?:\|\w+)?|title(?:\|\w+)?|author(?:\|\w+)?|subject(?:\|\w+)?|series(?:\|\w+)?|site|dir|sort|lang|available):[^:]+)$//so) {
        my($type, $value) = split(':', $1);
        next unless $type and $value;

        $value =~ s/^\s*//og;
        $value =~ s/\s*$//og;
        $type = 'sort_dir' if $type eq 'dir';

        if($type eq 'site') {
            # 'site' is the org shortname.  when using this, we also want 
            # to search at the requested org's depth
            my $e = new_editor();
            if(my $org = $e->search_actor_org_unit({shortname => $value})->[0]) {
                $arghash->{org_unit} = $org->id if $org;
                $arghash->{depth} = $e->retrieve_actor_org_unit_type($org->ou_type)->depth;
            } else {
                $logger->warn("'site:' query used on invalid org shortname: $value ... ignoring");
            }

        } elsif($type eq 'available') {
            # limit to available
            $arghash->{available} = 1 unless $value eq 'false' or $value eq '0';

        } elsif($type eq 'lang') {
            # collect languages into an array of languages
            $arghash->{language} = [] unless $arghash->{language};
            push(@{$arghash->{language}}, $value);

        } elsif($type =~ /^sort/o) {
            # sort and sort_dir modifiers
            $arghash->{$type} = $value;

        } else {
            # append the search term to the term under construction
            $search->{$type} =  {} unless $search->{$type};
            $search->{$type}->{term} =  
                ($search->{$type}->{term}) ? $search->{$type}->{term} . " $value" : $value;
        }
    }

    if($query) {
        # This is the front part of the string before any special tokens were parsed. 
        # Add this data to the default search class
        my $type = $arghash->{default_class} || 'keyword';
        $search->{$type} =  {} unless $search->{$type};
        $search->{$type}->{term} =
            ($search->{$type}->{term}) ? $search->{$type}->{term} . " $query" : $query;
    }

    # capture the original limit because the search method alters the limit internally
    my $ol = $arghash->{limit};

	my $sclient = OpenSRF::Utils::SettingsClient->new;

    (my $method = $self->api_name) =~ s/\.query//o;

    $method =~ s/multiclass/multiclass.staged/
        if $sclient->config_value(apps => 'open-ils.search',
            app_settings => 'use_staged_search') =~ /true/i;

    $arghash->{preferred_language} = $U->get_org_locale($arghash->{org_unit})
        unless $arghash->{preferred_language};

	$method = $self->method_lookup($method);
    my ($data) = $method->run($arghash, $docache);

    $arghash->{limit} = $ol if $ol;
    $data->{compiled_search} = $arghash;
    $data->{query} = $orig_query;

    $logger->info("compiled search is " . OpenSRF::Utils::JSON->perl2JSON($arghash));

    return $data;
}

__PACKAGE__->register_method(
	method		=> 'cat_search_z_style_wrapper',
	api_name	=> 'open-ils.search.biblio.zstyle',
	stream		=> 1,
	signature	=> q/@see open-ils.search.biblio.multiclass/);

__PACKAGE__->register_method(
	method		=> 'cat_search_z_style_wrapper',
	api_name	=> 'open-ils.search.biblio.zstyle.staff',
	stream		=> 1,
	signature	=> q/@see open-ils.search.biblio.multiclass/);

sub cat_search_z_style_wrapper {
	my $self = shift;
	my $client = shift;
	my $authtoken = shift;
	my $args = shift;

	my $cstore = OpenSRF::AppSession->connect('open-ils.cstore');

	my $ou = $cstore->request(
		'open-ils.cstore.direct.actor.org_unit.search',
		{ parent_ou => undef }
	)->gather(1);

	my $result = { service => 'native-evergreen-catalog', records => [] };
	my $searchhash = { limit => $$args{limit}, offset => $$args{offset}, org_unit => $ou->id };

	$$searchhash{searches}{title}{term} = $$args{search}{title} if $$args{search}{title};
	$$searchhash{searches}{author}{term} = $$args{search}{author} if $$args{search}{author};
	$$searchhash{searches}{subject}{term} = $$args{search}{subject} if $$args{search}{subject};
	$$searchhash{searches}{keyword}{term} = $$args{search}{keyword} if $$args{search}{keyword};

	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{tcn} if $$args{search}{tcn};
	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{isbn} if $$args{search}{isbn};
	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{issn} if $$args{search}{issn};
	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{publisher} if $$args{search}{publisher};
	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{pubdate} if $$args{search}{pubdate};
	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{item_type} if $$args{search}{item_type};

	my $list = the_quest_for_knowledge( $self, $client, $searchhash );

	if ($list->{count} > 0) {
		$result->{count} = $list->{count};

		my $records = $cstore->request(
			'open-ils.cstore.direct.biblio.record_entry.search.atomic',
			{ id => [ map { ( $_->[0] ) } @{$list->{ids}} ] }
		)->gather(1);

		for my $rec ( @$records ) {
			
			my $u = OpenILS::Utils::ModsParser->new();
                        $u->start_mods_batch( $rec->marc );
                        my $mods = $u->finish_mods_batch();

			push @{ $result->{records} }, { mvr => $mods, marcxml => $rec->marc, bibid => $rec->id };

		}

	}

    $cstore->disconnect();
	return $result;
}

# ----------------------------------------------------------------------------
# These are the main OPAC search methods
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method		=> 'the_quest_for_knowledge',
	api_name		=> 'open-ils.search.biblio.multiclass',
	signature	=> q/
		Performs a multi class biblio or metabib search
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
	api_name		=> 'open-ils.search.biblio.multiclass.staff',
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
	my( $self, $conn, $searchhash, $docache ) = @_;

	return { count => 0 } unless $searchhash and
		ref $searchhash->{searches} eq 'HASH';

	my $method = 'open-ils.storage.biblio.multiclass.search_fts';
	my $ismeta = 0;
	my @recs;

	if($self->api_name =~ /metabib/) {
		$ismeta = 1;
		$method =~ s/biblio/metabib/o;
	}


	my $offset	= $searchhash->{offset} || 0;
	my $limit	= $searchhash->{limit} || 10;
	my $end		= $offset + $limit - 1;

	# do some simple sanity checking
	if(!$searchhash->{searches} or
		( !grep { /^(?:title|author|subject|series|keyword)/ } keys %{$searchhash->{searches}} ) ) {
		return { count => 0 };
	}


	my $maxlimit = 5000;
	$searchhash->{offset}	= 0;
	$searchhash->{limit}		= $maxlimit;

	return { count => 0 } if $offset > $maxlimit;

	my @search;
	push( @search, ($_ => $$searchhash{$_})) for (sort keys %$searchhash);
	my $s = OpenSRF::Utils::JSON->perl2JSON(\@search);
	my $ckey = $pfx . md5_hex($method . $s);

	$logger->info("bib search for: $s");

	$searchhash->{limit} -= $offset;


    my $trim = 0;
	my $result = ($docache) ? search_cache($ckey, $offset, $limit) : undef;

	if(!$result) {

		$method .= ".staff" if($self->api_name =~ /staff/);
		$method .= ".atomic";
	
		for (keys %$searchhash) { 
			delete $$searchhash{$_} 
				unless defined $$searchhash{$_}; 
		}
	
		$result = $U->storagereq( $method, %$searchhash );
        $trim = 1;

	} else { 
		$docache = 0; 
	}

	return {count => 0} unless ($result && $$result[0]);

	@recs = @$result;

	my $count = ($ismeta) ? $result->[0]->[3] : $result->[0]->[2];

	if($docache) {
		# If we didn't get this data from the cache, put it into the cache
		# then return the correct offset of records
		$logger->debug("putting search cache $ckey\n");
		put_cache($ckey, $count, \@recs);
	}

    if($trim) {
        # if we have the full set of data, trim out 
        # the requested chunk based on limit and offset
        my @t;
        for ($offset..$end) {
            last unless $recs[$_];
            push(@t, $recs[$_]);
        }
        @recs = @t;
    }

	return { ids => \@recs, count => $count };
}


__PACKAGE__->register_method(
	method		=> 'staged_search',
	api_name	=> 'open-ils.search.biblio.multiclass.staged');
__PACKAGE__->register_method(
	method		=> 'staged_search',
	api_name	=> 'open-ils.search.biblio.multiclass.staged.staff',
	signature	=> q/@see open-ils.search.biblio.multiclass.staged/);
__PACKAGE__->register_method(
	method		=> 'staged_search',
	api_name	=> 'open-ils.search.metabib.multiclass.staged',
	signature	=> q/@see open-ils.search.biblio.multiclass.staged/);
__PACKAGE__->register_method(
	method		=> 'staged_search',
	api_name	=> 'open-ils.search.metabib.multiclass.staged.staff',
	signature	=> q/@see open-ils.search.biblio.multiclass.staged/);

sub staged_search {
	my($self, $conn, $search_hash, $docache) = @_;

    my $method = ($self->api_name =~ /metabib/) ?
        'open-ils.storage.metabib.multiclass.staged.search_fts':
        'open-ils.storage.biblio.multiclass.staged.search_fts';

    $method .= '.staff' if $self->api_name =~ /staff$/;
    $method .= '.atomic';

    my $search_duration;
    my $user_offset = $search_hash->{offset} || 0; # user-specified offset
    my $user_limit = $search_hash->{limit} || 10;
    $user_offset = ($user_offset >= 0) ? $user_offset : 0;
    $user_limit = ($user_limit >= 0) ? $user_limit : 10;


    # we're grabbing results on a per-superpage basis, which means the 
    # limit and offset should coincide with superpage boundaries
    $search_hash->{offset} = 0;
    $search_hash->{limit} = $superpage_size;

    # force a well-known check_limit
    $search_hash->{check_limit} = $superpage_size; 
    # restrict total tested to superpage size * number of superpages
    $search_hash->{core_limit} = $superpage_size * $max_superpages;

    # Set the configured estimation strategy, defaults to 'inclusion'.
	my $estimation_strategy = OpenSRF::Utils::SettingsClient
        ->new
        ->config_value(
            apps => 'open-ils.search', app_settings => 'estimation_strategy'
        ) || 'inclusion';
	$search_hash->{estimation_strategy} = $estimation_strategy;

    # pull any existing results from the cache
    my $key = search_cache_key($method, $search_hash);
    my $cache_data = $cache->get_cache($key) || {};

    # keep retrieving results until we find enough to 
    # fulfill the user-specified limit and offset
    my $all_results = [];
    my $page; # current superpage
    my $est_hit_count = 0;
    my $current_page_summary = {};
    my $global_summary = {checked => 0, visible => 0, excluded => 0, deleted => 0, total => 0};
    my $is_real_hit_count = 0;

    for($page = 0; $page < $max_superpages; $page++) {

        my $data = $cache_data->{$page};
        my $results;
        my $summary;

        $logger->debug("staged search: analyzing superpage $page");

        if($data) {
            # this window of results is already cached
            $logger->debug("staged search: found cached results");
            $summary = $data->{summary};
            $results = $data->{results};

        } else {
            # retrieve the window of results from the database
            $logger->debug("staged search: fetching results from the database");
            $search_hash->{skip_check} = $page * $superpage_size;
            my $start = time;
            $results = $U->storagereq($method, %$search_hash);
            $search_duration = time - $start;
            $logger->info("staged search: DB call took $search_duration seconds");
            $summary = shift(@$results);

            unless($summary) {
                $logger->info("search timed out: duration=$search_duration: params=".
                    OpenSRF::Utils::JSON->perl2JSON($search_hash));
                return {count => 0};
            }

            my $hc = $summary->{estimated_hit_count} || $summary->{visible};
            if($hc == 0) {
                $logger->info("search returned 0 results: duration=$search_duration: params=".
                    OpenSRF::Utils::JSON->perl2JSON($search_hash));
            }

            # Create backwards-compatible result structures
            if($self->api_name =~ /biblio/) {
                $results = [map {[$_->{id}]} @$results];
            } else {
                $results = [map {[$_->{id}, $_->{rel}, $_->{record}]} @$results];
            }

            $results = [grep {defined $_->[0]} @$results];
            cache_staged_search_page($key, $page, $summary, $results) if $docache;
        }

        $current_page_summary = $summary;

        # add the new set of results to the set under construction
        push(@$all_results, @$results);

        my $current_count = scalar(@$all_results);

        $est_hit_count = $summary->{estimated_hit_count} || $summary->{visible}
            if $page == 0;

        $logger->debug("staged search: located $current_count, with estimated hits=".
            $summary->{estimated_hit_count}." : visible=".$summary->{visible}.", checked=".$summary->{checked});

		if (defined($summary->{estimated_hit_count})) {
			$global_summary->{checked} += $summary->{checked};
			$global_summary->{visible} += $summary->{visible};
			$global_summary->{excluded} += $summary->{excluded};
			$global_summary->{deleted} += $summary->{deleted};
			$global_summary->{total} = $summary->{total};
		}

        # we've found all the possible hits
        last if $current_count == $summary->{visible}
            and not defined $summary->{estimated_hit_count};

        # we've found enough results to satisfy the requested limit/offset
        last if $current_count >= ($user_limit + $user_offset);

        # we've scanned all possible hits
        if($summary->{checked} < $superpage_size) {
            $est_hit_count = scalar(@$all_results);
            # we have all possible results in hand, so we know the final hit count
            $is_real_hit_count = 1;
            last;
        }
    }

    my @results = grep {defined $_} @$all_results[$user_offset..($user_offset + $user_limit - 1)];

	# refine the estimate if we have more than one superpage
	if ($page > 0 and not $is_real_hit_count) {
		if ($global_summary->{checked} >= $global_summary->{total}) {
			$est_hit_count = $global_summary->{visible};
		} else {
			my $updated_hit_count = $U->storagereq(
				'open-ils.storage.fts_paging_estimate',
				$global_summary->{checked},
				$global_summary->{visible},
				$global_summary->{excluded},
				$global_summary->{deleted},
				$global_summary->{total}
			);
			$est_hit_count = $updated_hit_count->{$estimation_strategy};
		}
	}

    return {
        count => $est_hit_count,
        core_limit => $search_hash->{core_limit},
        superpage_size => $search_hash->{check_limit},
        superpage_summary => $current_page_summary,
        ids => \@results
    };
}

# creates a unique token to represent the query in the cache
sub search_cache_key {
    my $method = shift;
    my $search_hash = shift;
	my @sorted;
    for my $key (sort keys %$search_hash) {
	    push(@sorted, ($key => $$search_hash{$key})) 
            unless $key eq 'limit' or 
                $key eq 'offset' or 
                $key eq 'skip_check';
    }
	my $s = OpenSRF::Utils::JSON->perl2JSON(\@sorted);
	return $pfx . md5_hex($method . $s);
}

sub cache_staged_search_page {
    # puts this set of results into the cache
    my($key, $page, $summary, $results) = @_;
    my $data = $cache->get_cache($key);
    $data ||= {};
    $data->{$page} = {
        summary => $summary,
        results => $results
    };

    $logger->info("staged search: cached with key=$key, superpage=$page, estimated=".
        $summary->{estimated_hit_count}.", visible=".$summary->{visible});

    $cache->put_cache($key, $data, $cache_timeout);
}

sub search_cache {

	my $key		= shift;
	my $offset	= shift;
	my $limit	= shift;
	my $start	= $offset;
	my $end		= $offset + $limit - 1;

	$logger->debug("searching cache for $key : $start..$end\n");

	return undef unless $cache;
	my $data = $cache->get_cache($key);

	return undef unless $data;

	my $count = $data->[0];
	$data = $data->[1];

	return undef unless $offset < $count;

	my @result;
	for( my $i = $offset; $i <= $end; $i++ ) {
		last unless my $d = $$data[$i];
		push( @result, $d );
	}

	$logger->debug("search_cache found ".scalar(@result)." items for count=$count, start=$start, end=$end");

	return \@result;
}


sub put_cache {
	my( $key, $count, $data ) = @_;
	return undef unless $cache;
	$logger->debug("search_cache putting ".
		scalar(@$data)." items at key $key with timeout $cache_timeout");
	$cache->put_cache($key, [ $count, $data ], $cache_timeout);
}






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
	my( $self, $client, $mrid, $args) = @_;

	warn "Grabbing mvr for $mrid\n";

	my ($mr, $evt) = _grab_metarecord($mrid);
	return $evt unless $mr;

	my $mvr = biblio_mrid_check_mvr($self, $client, $mr);
	$mvr = biblio_mrid_make_modsbatch( $self, $client, $mr ) unless $mvr;

	return $mvr unless ref($args);	

	# Here we find the lead record appropriate for the given filters 
	# and use that for the title and author of the metarecord
	my $format	= $$args{format};
	my $org		= $$args{org};
	my $depth	= $$args{depth};

	return $mvr unless $format or $org or $depth;

	my $method = "open-ils.storage.ordered.metabib.metarecord.records";
	$method = "$method.staff" if $self->api_name =~ /staff/o; 

	my $rec = $U->storagereq($method, $format, $org, $depth, 1);

	if( my $mods = $U->record_to_mvr($rec) ) {

		$mvr->title($mods->title);
		$mvr->title($mods->author);
		$logger->debug("mods_slim updating title and ".
			"author in mvr with ".$mods->title." : ".$mods->author);
	}

	return $mvr;
}

# converts a metarecord to an mvr
sub _mr_to_mvr {
	my $mr = shift;
	my $perl = OpenSRF::Utils::JSON->JSON2perl($mr->mods());
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

	my $evt;
	if(ref($mrid)) { $mr = $mrid; } 
	else { ($mr, $evt) = _grab_metarecord($mrid); }
	return $evt if $evt;

	warn "Checking mvr for mr " . $mr->id . "\n";

	return _mr_to_mvr($mr) if $mr->mods();
	return undef;
}

sub _grab_metarecord {
	my $mrid = shift;
	#my $e = OpenILS::Utils::Editor->new;
	my $e = new_editor();
	my $mr = $e->retrieve_metabib_metarecord($mrid) or return ( undef, $e->event );
	return ($mr);
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

	#my $e = OpenILS::Utils::Editor->new;
	my $e = new_editor();

	my $mr;
	if( ref($mrid) ) {
		$mr = $mrid;
		$mrid = $mr->id;
	} else {
		$mr = $e->retrieve_metabib_metarecord($mrid) 
			or return $e->event;
	}

	my $masterid = $mr->master_record;
	$logger->info("creating new mods batch for metarecord=$mrid, master record=$masterid");

	my $ids = $U->storagereq(
		'open-ils.storage.ordered.metabib.metarecord.records.staff.atomic', $mrid);
	return undef unless @$ids;

	my $master = $e->retrieve_biblio_record_entry($masterid)
		or return $e->event;

	# start the mods batch
	my $u = OpenILS::Utils::ModsParser->new();
	$u->start_mods_batch( $master->marc );

	# grab all of the sub-records and shove them into the batch
	my @ids = grep { $_ ne $masterid } @$ids;
	#my $subrecs = (@ids) ? $e->batch_retrieve_biblio_record_entry(\@ids) : [];

	my $subrecs = [];
	if(@$ids) {
		for my $i (@$ids) {
			my $r = $e->retrieve_biblio_record_entry($i);
			push( @$subrecs, $r ) if $r;
		}
	}

	for(@$subrecs) {
		$logger->debug("adding record ".$_->id." to mods batch for metarecord=$mrid");
		$u->push_mods_batch( $_->marc ) if $_->marc;
	}


	# finish up and send to the client
	my $mods = $u->finish_mods_batch();
	$mods->doc_id($mrid);
	$client->respond_complete($mods);


	# now update the mods string in the db
	my $string = OpenSRF::Utils::JSON->perl2JSON($mods->decast);
	$mr->mods($string);

	#$e = OpenILS::Utils::Editor->new(xact => 1);
	$e = new_editor(xact => 1);
	$e->update_metabib_metarecord($mr) 
		or $logger->error("Error setting mods text on metarecord $mrid : " . Dumper($e->event));
	$e->finish;

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

__PACKAGE__->register_method(
	method	=> "biblio_record_to_marc_html",
	api_name	=> "open-ils.search.authority.to_html" );

my $parser = XML::LibXML->new();
my $xslt = XML::LibXSLT->new();
my $marc_sheet;
my $slim_marc_sheet;
my $settings_client = OpenSRF::Utils::SettingsClient->new();

sub biblio_record_to_marc_html {
	my($self, $client, $recordid, $slim, $marcxml) = @_;

    my $sheet;
	my $dir = $settings_client->config_value("dirs", "xsl");

    if($slim) {
        unless($slim_marc_sheet) {
		    my $xsl = $settings_client->config_value(
			    "apps", "open-ils.search", "app_settings", 'marc_html_xsl_slim');
            if($xsl) {
		        $xsl = $parser->parse_file("$dir/$xsl");
		        $slim_marc_sheet = $xslt->parse_stylesheet($xsl);
            }
        }
        $sheet = $slim_marc_sheet;
    }

    unless($sheet) {
        unless($marc_sheet) {
            my $xsl_key = ($slim) ? 'marc_html_xsl_slim' : 'marc_html_xsl';
		    my $xsl = $settings_client->config_value(
			    "apps", "open-ils.search", "app_settings", 'marc_html_xsl');
		    $xsl = $parser->parse_file("$dir/$xsl");
		    $marc_sheet = $xslt->parse_stylesheet($xsl);
        }
        $sheet = $marc_sheet;
    }

    my $record;
    unless($marcxml) {
        my $e = new_editor();
        if($self->api_name =~ /authority/) {
            $record = $e->retrieve_authority_record_entry($recordid)
                or return $e->event;
        } else {
            $record = $e->retrieve_biblio_record_entry($recordid)
                or return $e->event;
        }
        $marcxml = $record->marc;
    }

	my $xmldoc = $parser->parse_string($marcxml);
	my $html = $sheet->transform($xmldoc);
	return $html->documentElement->toString();
}



__PACKAGE__->register_method(
	method	=> "retrieve_all_copy_statuses",
	api_name	=> "open-ils.search.config.copy_status.retrieve.all" );

sub retrieve_all_copy_statuses {
	my( $self, $client ) = @_;
	return new_editor()->retrieve_all_config_copy_status();
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
		[ org_id, callnumber_label, <status1_count>, <status2_count>,...]
		where statusx is a copy status name.  the statuses are sorted
		by id.
	NOTES

sub copy_count_summary {
	my( $self, $client, $rid, $org, $depth ) = @_;
	$org ||= 1;
	$depth ||= 0;
    my $data = $U->storagereq(
		'open-ils.storage.biblio.record_entry.status_copy_count.atomic', $rid, $org, $depth );

    return [ sort { $a->[1] cmp $b->[1] } @$data ];
}

__PACKAGE__->register_method(
	method		=> "copy_location_count_summary",
	api_name	=> "open-ils.search.biblio.copy_location_counts.summary.retrieve",
	notes 		=> <<"	NOTES");
	returns an array of these:
		[ org_id, callnumber_label, copy_location, <status1_count>, <status2_count>,...]
		where statusx is a copy status name.  the statuses are sorted
		by id.
	NOTES

sub copy_location_count_summary {
	my( $self, $client, $rid, $org, $depth ) = @_;
	$org ||= 1;
	$depth ||= 0;
    my $data = $U->storagereq(
		'open-ils.storage.biblio.record_entry.status_copy_location_count.atomic', $rid, $org, $depth );

    return [ sort { $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] } @$data ];
}

__PACKAGE__->register_method(
	method		=> "copy_count_location_summary",
	api_name	=> "open-ils.search.biblio.copy_counts.location.summary.retrieve",
	notes 		=> <<"	NOTES");
	returns an array of these:
		[ org_id, callnumber_label, <status1_count>, <status2_count>,...]
		where statusx is a copy status name.  the statuses are sorted
		by id.
	NOTES

sub copy_count_location_summary {
	my( $self, $client, $rid, $org, $depth ) = @_;
	$org ||= 1;
	$depth ||= 0;
    my $data = $U->storagereq(
        'open-ils.storage.biblio.record_entry.status_copy_location_count.atomic', $rid, $org, $depth );
    return [ sort { $a->[1] cmp $b->[1] } @$data ];
}


__PACKAGE__->register_method(
	method		=> "marc_search",
	api_name	=> "open-ils.search.biblio.marc.staff");

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
	my( $self, $conn, $args, $limit, $offset ) = @_;

	my $method = 'open-ils.storage.biblio.full_rec.multi_search';
	$method .= ".staff" if $self->api_name =~ /staff/;
	$method .= ".atomic";

	$limit ||= 10;
	$offset ||= 0;

	my @search;
	push( @search, ($_ => $$args{$_}) ) for (sort keys %$args);
	my $ckey = $pfx . md5_hex($method . OpenSRF::Utils::JSON->perl2JSON(\@search));

	my $recs = search_cache($ckey, $offset, $limit);

	if(!$recs) {
		$recs = $U->storagereq($method, %$args) || [];
		if( $recs ) {
			put_cache($ckey, scalar(@$recs), $recs);
			$recs = [ @$recs[$offset..($offset + ($limit - 1))] ];
		} else {
			$recs = [];
		}
	}

	my $count = 0;
	$count = $recs->[0]->[2] if $recs->[0] and $recs->[0]->[2];
	my @recs = map { $_->[0] } @$recs;

	return { ids => \@recs, count => $count };
}


__PACKAGE__->register_method(
	method	=> "biblio_search_isbn",
	api_name	=> "open-ils.search.biblio.isbn",
);

sub biblio_search_isbn { 
	my( $self, $client, $isbn ) = @_;
	$logger->debug("Searching ISBN $isbn");
	my $e = new_editor();
	my $recs = $U->storagereq(
		'open-ils.storage.id_list.biblio.record_entry.search.isbn.atomic', $isbn );
	return { ids => $recs, count => scalar(@$recs) };
}


__PACKAGE__->register_method(
	method	=> "biblio_search_issn",
	api_name	=> "open-ils.search.biblio.issn",
);

sub biblio_search_issn { 
	my( $self, $client, $issn ) = @_;
	$logger->debug("Searching ISSN $issn");
	my $e = new_editor();
	$issn =~ s/-/ /g;
	my $recs = $U->storagereq(
		'open-ils.storage.id_list.biblio.record_entry.search.issn.atomic', $issn );
	return { ids => $recs, count => scalar(@$recs) };
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
    authoritative => 1,
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
	return $U->cstorereq(
		'open-ils.cstore.direct.asset.copy.id_list.atomic', 
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
	return $U->cstorereq(
		'open-ils.cstore.direct.asset.call_number.search',
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
	api_name => 'open-ils.search.biblio.bib_level_map.retrieve.all');
__PACKAGE__->register_method (
	method => 'bib_extras',
	api_name => 'open-ils.search.biblio.audience_map.retrieve.all');

sub bib_extras {
	my $self = shift;

	my $e = new_editor();

	return $e->retrieve_all_config_lit_form_map()
		if( $self->api_name =~ /lit_form/ );

	return $e->retrieve_all_config_item_form_map()
		if( $self->api_name =~ /item_form_map/ );

	return $e->retrieve_all_config_item_type_map()
		if( $self->api_name =~ /item_type_map/ );

	return $e->retrieve_all_config_bib_level_map()
		if( $self->api_name =~ /bib_level_map/ );

	return $e->retrieve_all_config_audience_map()
		if( $self->api_name =~ /audience_map/ );

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

	#my $editor = OpenILS::Utils::Editor->new;
	my $editor = new_editor();
	my @res;
	for( @$ids ) {
		return $editor->event unless
			my $r = $editor->retrieve_biblio_record_entry($_);
		$r->clear_marc;
		push(@res, $r);
	}
	return \@res;
}



__PACKAGE__->register_method(
	method => 'rec_to_mr_rec_descriptors',
	api_name	=> 'open-ils.search.metabib.record_to_descriptors',
	signature	=> q/
		specialized method...
		Given a biblio record id or a metarecord id, 
		this returns a list of metabib.record_descriptor
		objects that live within the same metarecord
		@param args Object of args including:
	/
);

sub rec_to_mr_rec_descriptors {
	my( $self, $conn, $args ) = @_;

	my $rec = $$args{record};
	my $mrec	= $$args{metarecord};
	my $item_forms = $$args{item_forms};
	my $item_types	= $$args{item_types};
	my $item_lang	= $$args{item_lang};

	my $e = new_editor();
	my $recs;

	if( !$mrec ) {
		my $map = $e->search_metabib_metarecord_source_map({source => $rec});
		return $e->event unless @$map;
		$mrec = $$map[0]->metarecord;
	}

	$recs = $e->search_metabib_metarecord_source_map({metarecord => $mrec});
	return $e->event unless @$recs;

	my @recs = map { $_->source } @$recs;
	my $search = { record => \@recs };
	$search->{item_form} = $item_forms if $item_forms and @$item_forms;
	$search->{item_type} = $item_types if $item_types and @$item_types;
	$search->{item_lang} = $item_lang if $item_lang;

	my $desc = $e->search_metabib_record_descriptor($search);

	return { metarecord => $mrec, descriptors => $desc };
}




__PACKAGE__->register_method(
	method => 'copies_created_on',	
);


sub copies_created_on {
	my( $self, $conn, $auth, $org, $date ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
}


__PACKAGE__->register_method(
	method => 'fetch_age_protect',
	api_name => 'open-ils.search.copy.age_protect.retrieve.all',
);

sub fetch_age_protect {
	return new_editor()->retrieve_all_config_rule_age_hold_protect();
}


__PACKAGE__->register_method(
	method => 'copies_by_cn_label',
	api_name => 'open-ils.search.asset.copy.retrieve_by_cn_label',
);

__PACKAGE__->register_method(
	method => 'copies_by_cn_label',
	api_name => 'open-ils.search.asset.copy.retrieve_by_cn_label.staff',
);

sub copies_by_cn_label {
	my( $self, $conn, $record, $label, $circ_lib ) = @_;
	my $e = new_editor();
	my $cns = $e->search_asset_call_number({record => $record, label => $label, deleted => 'f'}, {idlist=>1});
	return [] unless @$cns;

	# show all non-deleted copies in the staff client ...
	if ($self->api_name =~ /staff$/o) {
		return $e->search_asset_copy({call_number => $cns, circ_lib => $circ_lib, deleted => 'f'}, {idlist=>1});
	}

	# ... otherwise, grab the copies ...
	my $copies = $e->search_asset_copy(
		[ {call_number => $cns, circ_lib => $circ_lib, deleted => 'f', opac_visible => 't'},
		  {flesh => 1, flesh_fields => { acp => [ qw/location status/] } }
		]
	);

	# ... and test for location and status visibility
	return [ map { ($U->is_true($_->location->opac_visible) && $U->is_true($_->status->opac_visible)) ? ($_->id) : () } @$copies ];
}



1;


