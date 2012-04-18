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
		my $u = OpenILS::Utils::ModsParser->new();  # FIXME: we really need a new parser for each object?
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
    method    => "record_id_to_mods",
    api_name  => "open-ils.search.biblio.record.mods.retrieve",
    argc      => 1,
    signature => {
        desc   => "Provide ID, we provide the MODS object with copy count.  " 
                . "Note: this method does NOT take an array of IDs like mods_slim.retrieve",    # FIXME: do it here too
        params => [
            { desc => 'Record ID', type => 'number' }
        ],
        return => {
            desc => 'MODS object', type => 'object'
        }
    }
);

# converts a record into a mods object with copy counts attached
sub record_id_to_mods {

    my( $self, $client, $org_id, $id ) = @_;

    my $mods_list = _records_to_mods( $id );
    my $mods_obj  = $mods_list->[0];
    my $cmethod   = $self->method_lookup("open-ils.search.biblio.record.copy_count");
    my ($count)   = $cmethod->run($org_id, $id);
    $mods_obj->copy_count($count);

    return $mods_obj;
}



__PACKAGE__->register_method(
    method        => "record_id_to_mods_slim",
    api_name      => "open-ils.search.biblio.record.mods_slim.retrieve",
    argc          => 1,
    authoritative => 1,
    signature     => {
        desc   => "Provide ID(s), we provide the MODS",
        params => [
            { desc => 'Record ID or array of IDs' }
        ],
        return => {
            desc => 'MODS object(s), event on error'
        }
    }
);

# converts a record into a mods object with NO copy counts attached
sub record_id_to_mods_slim {
	my( $self, $client, $id ) = @_;
	return undef unless defined $id;

	if(ref($id) and ref($id) == 'ARRAY') {
		return _records_to_mods( @$id );
	}
	my $mods_list = _records_to_mods( $id );
	my $mods_obj  = $mods_list->[0];
	return OpenILS::Event->new('BIBLIO_RECORD_ENTRY_NOT_FOUND') unless $mods_obj;
	return $mods_obj;
}



__PACKAGE__->register_method(
    method   => "record_id_to_mods_slim_batch",
    api_name => "open-ils.search.biblio.record.mods_slim.batch.retrieve",
    stream   => 1
);
sub record_id_to_mods_slim_batch {
	my($self, $conn, $id_list) = @_;
    $conn->respond(_records_to_mods($_)->[0]) for @$id_list;
    return undef;
}


# Returns the number of copies attached to a record based on org location
__PACKAGE__->register_method(
    method   => "record_id_to_copy_count",
    api_name => "open-ils.search.biblio.record.copy_count",
    signature => {
        desc => q/Returns a copy summary for the given record for the context org
            unit and all ancestor org units/,
        params => [
            {desc => 'Context org unit id', type => 'number'},
            {desc => 'Record ID', type => 'number'}
        ],
        return => {
            desc => q/summary object per org unit in the set, where the set
                includes the context org unit and all parent org units.  
                Object includes the keys "transcendant", "count", "org_unit", "depth", 
                "unshadow", "available".  Each is a count, except "org_unit" which is 
                the context org unit and "depth" which is the depth of the context org unit
            /,
            type => 'array'
        }
    }
);

__PACKAGE__->register_method(
    method        => "record_id_to_copy_count",
    api_name      => "open-ils.search.biblio.record.copy_count.staff",
    authoritative => 1,
    signature => {
        desc => q/Returns a copy summary for the given record for the context org
            unit and all ancestor org units/,
        params => [
            {desc => 'Context org unit id', type => 'number'},
            {desc => 'Record ID', type => 'number'}
        ],
        return => {
            desc => q/summary object per org unit in the set, where the set
                includes the context org unit and all parent org units.  
                Object includes the keys "transcendant", "count", "org_unit", "depth", 
                "unshadow", "available".  Each is a count, except "org_unit" which is 
                the context org unit and "depth" which is the depth of the context org unit
            /,
            type => 'array'
        }
    }
);

__PACKAGE__->register_method(
    method   => "record_id_to_copy_count",
    api_name => "open-ils.search.biblio.metarecord.copy_count",
    signature => {
        desc => q/Returns a copy summary for the given record for the context org
            unit and all ancestor org units/,
        params => [
            {desc => 'Context org unit id', type => 'number'},
            {desc => 'Record ID', type => 'number'}
        ],
        return => {
            desc => q/summary object per org unit in the set, where the set
                includes the context org unit and all parent org units.  
                Object includes the keys "transcendant", "count", "org_unit", "depth", 
                "unshadow", "available".  Each is a count, except "org_unit" which is 
                the context org unit and "depth" which is the depth of the context org unit
            /,
            type => 'array'
        }
    }
);

__PACKAGE__->register_method(
    method   => "record_id_to_copy_count",
    api_name => "open-ils.search.biblio.metarecord.copy_count.staff",
    signature => {
        desc => q/Returns a copy summary for the given record for the context org
            unit and all ancestor org units/,
        params => [
            {desc => 'Context org unit id', type => 'number'},
            {desc => 'Record ID', type => 'number'}
        ],
        return => {
            desc => q/summary object per org unit in the set, where the set
                includes the context org unit and all parent org units.  
                Object includes the keys "transcendant", "count", "org_unit", "depth", 
                "unshadow", "available".  Each is a count, except "org_unit" which is 
                the context org unit and "depth" which is the depth of the context org
                unit.  "depth" is always -1 when the count from a lasso search is
                performed, since depth doesn't mean anything in a lasso context.
            /,
            type => 'array'
        }
    }
);

sub record_id_to_copy_count {
    my( $self, $client, $org_id, $record_id ) = @_;

    return [] unless $record_id;

    my $key = $self->api_name =~ /metarecord/ ? 'metarecord' : 'record';
    my $staff = $self->api_name =~ /staff/ ? 't' : 'f';

    my $data = $U->cstorereq(
        "open-ils.cstore.json_query.atomic",
        { from => ['asset.' . $key  . '_copy_count' => $org_id => $record_id => $staff] }
    );

    my @count;
    for my $d ( @$data ) { # fix up the key name change required by stored-proc version
        $$d{count} = delete $$d{visible};
        push @count, $d;
    }

    return [ sort { $a->{depth} <=> $b->{depth} } @count ];
}

__PACKAGE__->register_method(
    method   => "record_has_holdable_copy",
    api_name => "open-ils.search.biblio.record.has_holdable_copy",
    signature => {
        desc => q/Returns a boolean indicating if a record has any holdable copies./,
        params => [
            {desc => 'Record ID', type => 'number'}
        ],
        return => {
            desc => q/bool indicating if the record has any holdable copies/,
            type => 'bool'
        }
    }
);

__PACKAGE__->register_method(
    method   => "record_has_holdable_copy",
    api_name => "open-ils.search.biblio.metarecord.has_holdable_copy",
    signature => {
        desc => q/Returns a boolean indicating if a record has any holdable copies./,
        params => [
            {desc => 'Record ID', type => 'number'}
        ],
        return => {
            desc => q/bool indicating if the record has any holdable copies/,
            type => 'bool'
        }
    }
);

sub record_has_holdable_copy {
    my($self, $client, $record_id ) = @_;

    return 0 unless $record_id;

    my $key = $self->api_name =~ /metarecord/ ? 'metarecord' : 'record';

    my $data = $U->cstorereq(
        "open-ils.cstore.json_query.atomic",
        { from => ['asset.' . $key . '_has_holdable_copy' => $record_id ] }
    );

    return ${@$data[0]}{'asset.' . $key . '_has_holdable_copy'} eq 't';

}

__PACKAGE__->register_method(
    method   => "biblio_search_tcn",
    api_name => "open-ils.search.biblio.tcn",
    argc     => 1,
    signature => {
        desc   => "Retrieve related record ID(s) given a TCN",
        params => [
            { desc => 'TCN', type => 'string' },
            { desc => 'Flag indicating to include deleted records', type => 'string' }
        ],
        return => {
            desc => 'Results object like: { "count": $i, "ids": [...] }',
            type => 'object'
        }
    }

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
    method   => "biblio_barcode_to_copy",
    api_name => "open-ils.search.asset.copy.find_by_barcode",
);
sub biblio_barcode_to_copy { 
	my( $self, $client, $barcode ) = @_;
	my( $copy, $evt ) = $U->fetch_copy_by_barcode($barcode);
	return $evt if $evt;
	return $copy;
}

__PACKAGE__->register_method(
    method   => "biblio_id_to_copy",
    api_name => "open-ils.search.asset.copy.batch.retrieve",
);
sub biblio_id_to_copy { 
	my( $self, $client, $ids ) = @_;
	$logger->info("Fetching copies @$ids");
	return $U->cstorereq(
		"open-ils.cstore.direct.asset.copy.search.atomic", { id => $ids } );
}


__PACKAGE__->register_method(
	method	=> "biblio_id_to_uris",
	api_name=> "open-ils.search.asset.uri.retrieve_by_bib",
	argc	=> 2, 
    stream  => 1,
    signature => q#
        @param BibID Which bib record contains the URIs
        @param OrgID Where to look for URIs
        @param OrgDepth Range adjustment for OrgID
        @return A stream or list of 'auri' objects
    #

);
sub biblio_id_to_uris { 
	my( $self, $client, $bib, $org, $depth ) = @_;
    die "Org ID required" unless defined($org);
    die "Bib ID required" unless defined($bib);

    my @params;
    push @params, $depth if (defined $depth);

	my $ids = $U->cstorereq( "open-ils.cstore.json_query.atomic",
        {   select  => { auri => [ 'id' ] },
            from    => {
                acn => {
                    auricnm => {
                        field   => 'call_number',
                        fkey    => 'id',
                        join    => {
                            auri    => {
                                field => 'id',
                                fkey => 'uri',
                                filter  => { active => 't' }
                            }
                        }
                    }
                }
            },
            where   => {
                '+acn'  => {
                    record      => $bib,
                    owning_lib  => {
                        in  => {
                            select  => { aou => [ { column => 'id', transform => 'actor.org_unit_descendants', params => \@params, result_field => 'id' } ] },
                            from    => 'aou',
                            where   => { id => $org },
                            distinct=> 1
                        }
                    }
                }
            },
            distinct=> 1,
        }
    );

	my $uris = $U->cstorereq(
		"open-ils.cstore.direct.asset.uri.search.atomic",
        { id => [ map { (values %$_) } @$ids ] }
    );

    $client->respond($_) for (@$uris);

    return undef;
}


__PACKAGE__->register_method(
    method    => "copy_retrieve",
    api_name  => "open-ils.search.asset.copy.retrieve",
    argc      => 1,
    signature => {
        desc   => 'Retrieve a copy object based on the Copy ID',
        params => [
            { desc => 'Copy ID', type => 'number'}
        ],
        return => {
            desc => 'Copy object, event on error'
        }
    }
);

sub copy_retrieve {
	my( $self, $client, $cid ) = @_;
	my( $copy, $evt ) = $U->fetch_copy($cid);
	return $evt || $copy;
}

__PACKAGE__->register_method(
    method   => "volume_retrieve",
    api_name => "open-ils.search.asset.call_number.retrieve"
);
sub volume_retrieve {
	my( $self, $client, $vid ) = @_;
	my $e = new_editor();
	my $vol = $e->retrieve_asset_call_number($vid) or return $e->event;
	return $vol;
}

__PACKAGE__->register_method(
    method        => "fleshed_copy_retrieve_batch",
    api_name      => "open-ils.search.asset.copy.fleshed.batch.retrieve",
    authoritative => 1,
);

sub fleshed_copy_retrieve_batch { 
	my( $self, $client, $ids ) = @_;
	$logger->info("Fetching fleshed copies @$ids");
	return $U->cstorereq(
		"open-ils.cstore.direct.asset.copy.search.atomic",
		{ id => $ids },
		{ flesh => 1, 
		  flesh_fields => { acp => [ qw/ circ_lib location status stat_cat_entries parts / ] }
		});
}


__PACKAGE__->register_method(
    method   => "fleshed_copy_retrieve",
    api_name => "open-ils.search.asset.copy.fleshed.retrieve",
);

sub fleshed_copy_retrieve { 
	my( $self, $client, $id ) = @_;
	my( $c, $e) = $U->fetch_fleshed_copy($id);
	return $e || $c;
}


__PACKAGE__->register_method(
    method        => 'fleshed_by_barcode',
    api_name      => "open-ils.search.asset.copy.fleshed2.find_by_barcode",
    authoritative => 1,
);
sub fleshed_by_barcode {
	my( $self, $conn, $barcode ) = @_;
	my $e = new_editor();
	my $copyid = $e->search_asset_copy(
		{barcode => $barcode, deleted => 'f'}, {idlist=>1})->[0]
		or return $e->event;
	return fleshed_copy_retrieve2( $self, $conn, $copyid);
}


__PACKAGE__->register_method(
    method        => "fleshed_copy_retrieve2",
    api_name      => "open-ils.search.asset.copy.fleshed2.retrieve",
    authoritative => 1,
);

sub fleshed_copy_retrieve2 { 
	my( $self, $client, $id ) = @_;
	my $e = new_editor();
	my $copy = $e->retrieve_asset_copy(
		[
			$id,
            {
                flesh        => 2,
                flesh_fields => {
                    acp => [
                        qw/ location status stat_cat_entry_copy_maps notes age_protect parts peer_record_maps /
                    ],
                    ascecm => [qw/ stat_cat stat_cat_entry /],
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
    method        => 'flesh_copy_custom',
    api_name      => 'open-ils.search.asset.copy.fleshed.custom',
    authoritative => 1,
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
    method   => "biblio_barcode_to_title",
    api_name => "open-ils.search.biblio.find_by_barcode",
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
    method        => 'title_id_by_item_barcode',
    api_name      => 'open-ils.search.bib_id.by_barcode',
    authoritative => 1,
    signature => { 
        desc   => 'Retrieve bib record id associated with the copy identified by the given barcode',
        params => [
            { desc => 'Item barcode', type => 'string' }
        ],
        return => {
            desc => 'Bib record id.'
        }
    }
);

__PACKAGE__->register_method(
    method        => 'title_id_by_item_barcode',
    api_name      => 'open-ils.search.multi_home.bib_ids.by_barcode',
    authoritative => 1,
    signature => {
        desc   => 'Retrieve bib record ids associated with the copy identified by the given barcode.  This includes peer bibs for Multi-Home items.',
        params => [
            { desc => 'Item barcode', type => 'string' }
        ],
        return => {
            desc => 'Array of bib record ids.  First element is the native bib for the item.'
        }
    }
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

    if( $self->api_name =~ /multi_home/ ) {
        my $multi_home_list = $e->search_biblio_peer_bib_copy_map(
            [
                { target_copy => $$copies[0]->id }
            ]
        );
        my @temp =  map { $_->peer_record } @{ $multi_home_list };
        unshift @temp, $$copies[0]->call_number->record->id;
        return \@temp;
    } else {
        return $$copies[0]->call_number->record->id;
    }
}

__PACKAGE__->register_method(
    method        => 'find_peer_bibs',
    api_name      => 'open-ils.search.peer_bibs.test',
    authoritative => 1,
    signature => {
        desc   => 'Tests to see if the specified record is a peer record.',
        params => [
            { desc => 'Biblio record entry Id', type => 'number' }
        ],
        return => {
            desc => 'True if specified id can be found in biblio.peer_bib_copy_map.peer_record.',
            type => 'bool'
        }
    }
);

__PACKAGE__->register_method(
    method        => 'find_peer_bibs',
    api_name      => 'open-ils.search.peer_bibs',
    authoritative => 1,
    signature => {
        desc   => 'Return acps and mvrs for multi-home items linked to specified peer record.',
        params => [
            { desc => 'Biblio record entry Id', type => 'number' }
        ],
        return => {
            desc => '{ records => Array of mvrs, items => array of acps }',
        }
    }
);


sub find_peer_bibs {
	my( $self, $client, $doc_id ) = @_;
    my $e = new_editor();

    my $multi_home_list = $e->search_biblio_peer_bib_copy_map(
        [
            { peer_record => $doc_id },
            {
                flesh => 2,
                flesh_fields => {
                    bpbcm => [ 'target_copy', 'peer_type' ],
                    acp => [ 'call_number', 'location', 'status', 'peer_record_maps' ]
                }
            }
        ]
    );

    if ($self->api_name =~ /test/) {
        return scalar( @{$multi_home_list} ) > 0 ? 1 : 0;
    }

    if (scalar(@{$multi_home_list})==0) {
        return [];
    }

    # create a unique hash of the primary record MVRs for foreign copies
    # XXX PLEASE let's change to unAPI2 (supports foreign copies) in the TT opac?!?
    my %rec_hash = map {
        ($_->target_copy->call_number->record, _records_to_mods( $_->target_copy->call_number->record )->[0])
    } @$multi_home_list;

    # set the foreign_copy_maps field to an empty array
    map { $rec_hash{$_}->foreign_copy_maps([]) } keys( %rec_hash );

    # push the maps onto the correct MVRs
    for (@$multi_home_list) {
        push(
            @{$rec_hash{ $_->target_copy->call_number->record }->foreign_copy_maps()},
            $_
        );
    }

    return [sort {$a->title cmp $b->title} values(%rec_hash)];
};

__PACKAGE__->register_method(
    method   => "biblio_copy_to_mods",
    api_name => "open-ils.search.biblio.copy.mods.retrieve",
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


=head1 NAME

OpenILS::Application::Search::Biblio

=head1 DESCRIPTION

=head2 API METHODS

=head3 open-ils.search.biblio.multiclass.query (arghash, query, docache)

For arghash and docache, see B<open-ils.search.biblio.multiclass>.

The query argument is a string, but built like a hash with key: value pairs.
Recognized search keys include: 

 keyword (kw) - search keyword(s) *
 author  (au) - search author(s)  *
 name    (au) - same as author    *
 title   (ti) - search title      *
 subject (su) - search subject    *
 series  (se) - search series     *
 lang - limit by language (specifiy multiple langs with lang:l1 lang:l2 ...)
 site - search at specified org unit, corresponds to actor.org_unit.shortname
 pref_ou - extend search to specified org unit, corresponds to actor.org_unit.shortname
 sort - sort type (title, author, pubdate)
 dir  - sort direction (asc, desc)
 available - if set to anything other than "false" or "0", limits to available items

* Searching keyword, author, title, subject, and series supports additional search 
subclasses, specified with a "|".  For example, C<title|proper:gone with the wind>.

For more, see B<config.metabib_field>.

=cut

foreach (qw/open-ils.search.biblio.multiclass.query
            open-ils.search.biblio.multiclass.query.staff
            open-ils.search.metabib.multiclass.query
            open-ils.search.metabib.multiclass.query.staff/)
{
__PACKAGE__->register_method(
    api_name  => $_,
    method    => 'multiclass_query',
    signature => {
        desc   => 'Perform a search query.  The .staff version of the call includes otherwise hidden hits.',
        params => [
            {name => 'arghash', desc => 'Arg hash (see open-ils.search.biblio.multiclass)',         type => 'object'},
            {name => 'query',   desc => 'Raw human-readable query (see perldoc '. __PACKAGE__ .')', type => 'string'},
            {name => 'docache', desc => 'Flag for caching (see open-ils.search.biblio.multiclass)', type => 'object'},
        ],
        return => {
            desc => 'Search results from query, like: { "count" : $count, "ids" : [ [ $id, $relevancy, $total ], ...] }',
            type => 'object',       # TODO: update as miker's new elements are included
        }
    }
);
}

sub multiclass_query {
    my($self, $conn, $arghash, $query, $docache) = @_;

    $logger->debug("initial search query => $query");
    my $orig_query = $query;

    $query =~ s/\+/ /go;
    $query =~ s/^\s+//go;

    # convert convenience classes (e.g. kw for keyword) to the full class name
    # ensure that the convenience class isn't part of a word (e.g. 'playhouse')
    $query =~ s/(^|\s)kw(:|\|)/$1keyword$2/go;
    $query =~ s/(^|\s)ti(:|\|)/$1title$2/go;
    $query =~ s/(^|\s)au(:|\|)/$1author$2/go;
    $query =~ s/(^|\s)su(:|\|)/$1subject$2/go;
    $query =~ s/(^|\s)se(:|\|)/$1series$2/go;
    $query =~ s/(^|\s)name(:|\|)/$1author$2/og;

    $logger->debug("cleansed query string => $query");
    my $search = {};

    my $simple_class_re  = qr/((?:\w+(?:\|\w+)?):[^:]+?)$/;
    my $class_list_re    = qr/(?:keyword|title|author|subject|series)/;
    my $modifier_list_re = qr/(?:site|dir|sort|lang|available|preflib)/;

    my $tmp_value = '';
    while ($query =~ s/$simple_class_re//so) {

        my $qpart = $1;
        my $where = index($qpart,':');
        my $type  = substr($qpart, 0, $where++);
        my $value = substr($qpart, $where);

        if ($type !~ /^(?:$class_list_re|$modifier_list_re)/o) {
            $tmp_value = "$qpart $tmp_value";
            next;
        }

        if ($type =~ /$class_list_re/o ) {
            $value .= $tmp_value;
            $tmp_value = '';
        }

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
        } elsif($type eq 'pref_ou') {
            # 'pref_ou' is the preferred org shortname.
            my $e = new_editor();
            if(my $org = $e->search_actor_org_unit({shortname => $value})->[0]) {
                $arghash->{pref_ou} = $org->id if $org;
            } else {
                $logger->warn("'pref_ou:' query used on invalid org shortname: $value ... ignoring");
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

    $query .= " $tmp_value";
    $query =~ s/\s+/ /go;
    $query =~ s/^\s+//go;
    $query =~ s/\s+$//go;

    my $type = $arghash->{default_class} || 'keyword';
    $type = ($type eq '-') ? 'keyword' : $type;
    $type = ($type !~ /^(title|author|keyword|subject|series)(?:\|\w+)?$/o) ? 'keyword' : $type;

    if($query) {
        # This is the front part of the string before any special tokens were
        # parsed OR colon-separated strings that do not denote a class.
        # Add this data to the default search class
        $search->{$type} =  {} unless $search->{$type};
        $search->{$type}->{term} =
            ($search->{$type}->{term}) ? $search->{$type}->{term} . " $query" : $query;
    }
    my $real_search = $arghash->{searches} = { $type => { term => $orig_query } };

    # capture the original limit because the search method alters the limit internally
    my $ol = $arghash->{limit};

	my $sclient = OpenSRF::Utils::SettingsClient->new;

    (my $method = $self->api_name) =~ s/\.query//o;

    $method =~ s/multiclass/multiclass.staged/
        if $sclient->config_value(apps => 'open-ils.search',
            app_settings => 'use_staged_search') =~ /true/i;

    # XXX This stops the session locale from doing the right thing.
    # XXX Revisit this and have it translate to a lang instead of a locale.
    #$arghash->{preferred_language} = $U->get_org_locale($arghash->{org_unit})
    #    unless $arghash->{preferred_language};

	$method = $self->method_lookup($method);
    my ($data) = $method->run($arghash, $docache);

    $arghash->{searches} = $search if (!$data->{complex_query});

    $arghash->{limit} = $ol if $ol;
    $data->{compiled_search} = $arghash;
    $data->{query} = $orig_query;

    $logger->info("compiled search is " . OpenSRF::Utils::JSON->perl2JSON($arghash));

    return $data;
}

__PACKAGE__->register_method(
    method    => 'cat_search_z_style_wrapper',
    api_name  => 'open-ils.search.biblio.zstyle',
    stream    => 1,
    signature => q/@see open-ils.search.biblio.multiclass/
);

__PACKAGE__->register_method(
    method    => 'cat_search_z_style_wrapper',
    api_name  => 'open-ils.search.biblio.zstyle.staff',
    stream    => 1,
    signature => q/@see open-ils.search.biblio.multiclass/
);

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

	$$searchhash{searches}{title}{term}   = $$args{search}{title}   if $$args{search}{title};
	$$searchhash{searches}{author}{term}  = $$args{search}{author}  if $$args{search}{author};
	$$searchhash{searches}{subject}{term} = $$args{search}{subject} if $$args{search}{subject};
	$$searchhash{searches}{keyword}{term} = $$args{search}{keyword} if $$args{search}{keyword};
	$$searchhash{searches}{'identifier|isbn'}{term} = $$args{search}{isbn} if $$args{search}{isbn};
	$$searchhash{searches}{'identifier|issn'}{term} = $$args{search}{issn} if $$args{search}{issn};

	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{tcn}       if $$args{search}{tcn};
	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{publisher} if $$args{search}{publisher};
	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{pubdate}   if $$args{search}{pubdate};
	$$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{item_type} if $$args{search}{item_type};

	my $list = the_quest_for_knowledge( $self, $client, $searchhash );

	if ($list->{count} > 0 and @{$list->{ids}}) {
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
    method    => 'the_quest_for_knowledge',
    api_name  => 'open-ils.search.biblio.multiclass',
    signature => {
        desc => "Performs a multi class biblio or metabib search",
        params => [
            {
                desc => "A search hash with keys: "
                      . "searches, org_unit, depth, limit, offset, format, sort, sort_dir.  "
                      . "See perldoc " . __PACKAGE__ . " for more detail",
                type => 'object',
            },
            {
                desc => "A flag to enable/disable searching and saving results in cache (default OFF)",
                type => 'string',
            }
        ],
        return => {
            desc => 'An object of the form: '
                  . '{ "count" : $count, "ids" : [ [ $id, $relevancy, $total ], ...] }',
        }
    }
);

=head3 open-ils.search.biblio.multiclass (search-hash, docache)

The search-hash argument can have the following elements:

    searches: { "$class" : "$value", ...}           [REQUIRED]
    org_unit: The org id to focus the search at
    depth   : The org depth     
    limit   : The search limit      default: 10
    offset  : The search offset     default:  0
    format  : The MARC format
    sort    : What field to sort the results on? [ author | title | pubdate ]
    sort_dir: What direction do we sort? [ asc | desc ]
    tag_circulated_records : Boolean, if true, records that are in the user's visible checkout history
        will be tagged with an additional value ("1") as the last value in the record ID array for
        each record.  Requires the 'authtoken'
    authtoken : Authentication token string;  When actions are performed that require a user login
        (e.g. tagging circulated records), the authentication token is required

The searches element is required, must have a hashref value, and the hashref must contain at least one 
of the following classes as a key:

    title
    author
    subject
    series
    keyword

The value paired with a key is the associated search string.

The docache argument enables/disables searching and saving results in cache (default OFF).

The return object, if successful, will look like:

    { "count" : $count, "ids" : [ [ $id, $relevancy, $total ], ...] }

=cut

__PACKAGE__->register_method(
    method    => 'the_quest_for_knowledge',
    api_name  => 'open-ils.search.biblio.multiclass.staff',
    signature => q/The .staff search includes hidden bibs, hidden items and bibs with no items.  Otherwise, @see open-ils.search.biblio.multiclass/
);
__PACKAGE__->register_method(
    method    => 'the_quest_for_knowledge',
    api_name  => 'open-ils.search.metabib.multiclass',
    signature => q/@see open-ils.search.biblio.multiclass/
);
__PACKAGE__->register_method(
    method    => 'the_quest_for_knowledge',
    api_name  => 'open-ils.search.metabib.multiclass.staff',
    signature => q/The .staff search includes hidden bibs, hidden items and bibs with no items.  Otherwise, @see open-ils.search.biblio.multiclass/
);

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

	# do some simple sanity checking
	if(!$searchhash->{searches} or
		( !grep { /^(?:title|author|subject|series|keyword|identifier\|is[bs]n)/ } keys %{$searchhash->{searches}} ) ) {
		return { count => 0 };
	}

    my $offset = $searchhash->{offset} ||  0;   # user value or default in local var now
    my $limit  = $searchhash->{limit}  || 10;   # user value or default in local var now
    my $end    = $offset + $limit - 1;

	my $maxlimit = 5000;
    $searchhash->{offset} = 0;                  # possible user value overwritten in hash
    $searchhash->{limit}  = $maxlimit;          # possible user value overwritten in hash

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
		$docache = 0;   # results came FROM cache, so we don't write back
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
    method    => 'staged_search',
    api_name  => 'open-ils.search.biblio.multiclass.staged',
    signature => {
        desc   => 'Staged search filters out unavailable items.  This means that it relies on an estimation strategy for determining ' .
                  'how big a "raw" search result chunk (i.e. a "superpage") to obtain prior to filtering.  See "estimation_strategy" in your SRF config.',
        params => [
            {
                desc => "A search hash with keys: "
                      . "searches, limit, offset.  The others are optional, but the 'searches' key/value pair is required, with the value being a hashref.  "
                      . "See perldoc " . __PACKAGE__ . " for more detail",
                type => 'object',
            },
            {
                desc => "A flag to enable/disable searching and saving results in cache, including facets (default OFF)",
                type => 'string',
            }
        ],
        return => {
            desc => 'Hash with keys: count, core_limit, superpage_size, superpage_summary, facet_key, ids.  '
                  . 'The superpage_summary value is a hashref that includes keys: estimated_hit_count, visible.',
            type => 'object',
        }
    }
);
__PACKAGE__->register_method(
    method    => 'staged_search',
    api_name  => 'open-ils.search.biblio.multiclass.staged.staff',
    signature => q/The .staff search includes hidden bibs, hidden items and bibs with no items.  Otherwise, @see open-ils.search.biblio.multiclass.staged/
);
__PACKAGE__->register_method(
    method    => 'staged_search',
    api_name  => 'open-ils.search.metabib.multiclass.staged',
    signature => q/@see open-ils.search.biblio.multiclass.staged/
);
__PACKAGE__->register_method(
    method    => 'staged_search',
    api_name  => 'open-ils.search.metabib.multiclass.staged.staff',
    signature => q/The .staff search includes hidden bibs, hidden items and bibs with no items.  Otherwise, @see open-ils.search.biblio.multiclass.staged/
);

sub staged_search {
	my($self, $conn, $search_hash, $docache) = @_;

    my $IAmMetabib = ($self->api_name =~ /metabib/) ? 1 : 0;

    my $method = $IAmMetabib?
        'open-ils.storage.metabib.multiclass.staged.search_fts':
        'open-ils.storage.biblio.multiclass.staged.search_fts';

    $method .= '.staff' if $self->api_name =~ /staff$/;
    $method .= '.atomic';
                
    return {count => 0} unless (
        $search_hash and 
        $search_hash->{searches} and 
        scalar( keys %{$search_hash->{searches}} ));

    my $search_duration;
    my $user_offset = $search_hash->{offset} ||  0; # user-specified offset
    my $user_limit  = $search_hash->{limit}  || 10;
    my $ignore_facet_classes  = $search_hash->{ignore_facet_classes};
    $user_offset = ($user_offset >= 0) ? $user_offset :  0;
    $user_limit  = ($user_limit  >= 0) ? $user_limit  : 10;


    # we're grabbing results on a per-superpage basis, which means the 
    # limit and offset should coincide with superpage boundaries
    $search_hash->{offset} = 0;
    $search_hash->{limit} = $superpage_size;

    # force a well-known check_limit
    $search_hash->{check_limit} = $superpage_size; 
    # restrict total tested to superpage size * number of superpages
    $search_hash->{core_limit}  = $superpage_size * $max_superpages;

    # Set the configured estimation strategy, defaults to 'inclusion'.
	my $estimation_strategy = OpenSRF::Utils::SettingsClient
        ->new
        ->config_value(
            apps => 'open-ils.search', app_settings => 'estimation_strategy'
        ) || 'inclusion';
	$search_hash->{estimation_strategy} = $estimation_strategy;

    # pull any existing results from the cache
    my $key = search_cache_key($method, $search_hash);
    my $facet_key = $key.'_facets';
    my $cache_data = $cache->get_cache($key) || {};

    # keep retrieving results until we find enough to 
    # fulfill the user-specified limit and offset
    my $all_results = [];
    my $page; # current superpage
    my $est_hit_count = 0;
    my $current_page_summary = {};
    my $global_summary = {checked => 0, visible => 0, excluded => 0, deleted => 0, total => 0};
    my $is_real_hit_count = 0;
    my $new_ids = [];

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
            $summary = shift(@$results) if $results;

            unless($summary) {
                $logger->info("search timed out: duration=$search_duration: params=".
                    OpenSRF::Utils::JSON->perl2JSON($search_hash));
                return {count => 0};
            }

            $logger->info("staged search: DB call took $search_duration seconds and returned ".scalar(@$results)." rows, including summary");

            my $hc = $summary->{estimated_hit_count} || $summary->{visible};
            if($hc == 0) {
                $logger->info("search returned 0 results: duration=$search_duration: params=".
                    OpenSRF::Utils::JSON->perl2JSON($search_hash));
            }

            # Create backwards-compatible result structures
            if($IAmMetabib) {
                $results = [map {[$_->{id}, $_->{rel}, $_->{record}]} @$results];
            } else {
                $results = [map {[$_->{id}]} @$results];
            }

            push @$new_ids, grep {defined($_)} map {$_->[0]} @$results;
            $results = [grep {defined $_->[0]} @$results];
            cache_staged_search_page($key, $page, $summary, $results) if $docache;
        }

        tag_circulated_records($search_hash->{authtoken}, $results, $IAmMetabib) 
            if $search_hash->{tag_circulated_records} and $search_hash->{authtoken};

        $current_page_summary = $summary;

        # add the new set of results to the set under construction
        push(@$all_results, @$results);

        my $current_count = scalar(@$all_results);

        $est_hit_count = $summary->{estimated_hit_count} || $summary->{visible}
            if $page == 0;

        $logger->debug("staged search: located $current_count, with estimated hits=".
            $summary->{estimated_hit_count}." : visible=".$summary->{visible}.", checked=".$summary->{checked});

		if (defined($summary->{estimated_hit_count})) {
            foreach (qw/ checked visible excluded deleted /) {
                $global_summary->{$_} += $summary->{$_};
            }
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

    $conn->respond_complete(
        {
            count             => $est_hit_count,
            core_limit        => $search_hash->{core_limit},
            superpage_size    => $search_hash->{check_limit},
            superpage_summary => $current_page_summary,
            facet_key         => $facet_key,
            ids               => \@results
        }
    );

    cache_facets($facet_key, $new_ids, $IAmMetabib, $ignore_facet_classes) if $docache;

    return undef;
}

sub tag_circulated_records {
    my ($auth, $results, $metabib) = @_;
    my $e = new_editor(authtoken => $auth);
    return $results unless $e->checkauth;

    my $query = {
        select   => { acn => [{ column => 'record', alias => 'tagme' }] }, 
        from     => { acp => 'acn' }, 
        where    => { id => { in => { from => ['action.usr_visible_circ_copies', $e->requestor->id] } } },
        distinct => 1
    };

    if ($metabib) {
        $query = {
            select   => { mmsm => [{ column => 'metarecord', alias => 'tagme' }] },
            from     => 'mmsm',
            where    => { source => { in => $query } },
            distinct => 1
        };
    }

    # Give me the distinct set of bib records that exist in the user's visible circulation history
    my $circ_recs = $e->json_query( $query );

    # if the record appears in the circ history, push a 1 onto 
    # the rec array structure to indicate truthiness
    for my $rec (@$results) {
        push(@$rec, 1) if grep { $_->{tagme} eq $$rec[0] } @$circ_recs;
    }

    $results
}

# creates a unique token to represent the query in the cache
sub search_cache_key {
    my $method = shift;
    my $search_hash = shift;
	my @sorted;
    for my $key (sort keys %$search_hash) {
	    push(@sorted, ($key => $$search_hash{$key})) 
            unless $key eq 'limit'  or 
                   $key eq 'offset' or 
                   $key eq 'skip_check';
    }
	my $s = OpenSRF::Utils::JSON->perl2JSON(\@sorted);
	return $pfx . md5_hex($method . $s);
}

sub retrieve_cached_facets {
    my $self   = shift;
    my $client = shift;
    my $key    = shift;
    my $limit    = shift;

    return undef unless ($key and $key =~ /_facets$/);

    my $blob = $cache->get_cache($key) || {};

    my $facets = {};
    if ($limit) {
       for my $f ( keys %$blob ) {
            my @sorted = map{ { $$_[1] => $$_[0] } } sort {$$b[0] <=> $$a[0] || $$a[1] cmp $$b[1]} map { [$$blob{$f}{$_}, $_] } keys %{ $$blob{$f} };
            @sorted = @sorted[0 .. $limit - 1] if (scalar(@sorted) > $limit);
            for my $s ( @sorted ) {
                my ($k) = keys(%$s);
                my ($v) = values(%$s);
                $$facets{$f}{$k} = $v;
            }
        }
    } else {
        $facets = $blob;
    }

    return $facets;
}

__PACKAGE__->register_method(
    method   => "retrieve_cached_facets",
    api_name => "open-ils.search.facet_cache.retrieve",
    signature => {
        desc   => 'Returns facet data derived from a specific search based on a key '.
                  'generated by open-ils.search.biblio.multiclass.staged and friends.',
        params => [
            {
                desc => "The facet cache key returned with the initial search as the facet_key hash value",
                type => 'string',
            }
        ],
        return => {
            desc => 'Two level hash of facet values.  Top level key is the facet id defined on the config.metabib_field table.  '.
                    'Second level key is a string facet value.  Datum attached to each facet value is the number of distinct records, '.
                    'or metarecords for a metarecord search, which use that facet value and are visible to the search at the time of '.
                    'facet retrieval.  These counts are calculated for all superpages that have been checked for visibility.',
            type => 'object',
        }
    }
);


sub cache_facets {
    # add facets for this search to the facet cache
    my($key, $results, $metabib, $ignore) = @_;
    my $data = $cache->get_cache($key);
    $data ||= {};

    return undef unless (@$results);

    # The query we're constructing
    #
    # select  mfae.field as id,
    #         mfae.value,
    #         count(distinct mmrsm.appropriate-id-field )
    #   from  metabib.facet_entry mfae
    #         join metabib.metarecord_sourc_map mmrsm on (mfae.source = mmrsm.source)
    #   where mmrsm.appropriate-id-field in IDLIST
    #   group by 1,2;

    my $count_field = $metabib ? 'metarecord' : 'source';
    my $query = {   
        select  => {
            mfae => [ { column => 'field', alias => 'id'}, 'value' ],
            mmrsm => [{
                transform => 'count',
                distinct => 1,
                column => $count_field,
                alias => 'count',
                aggregate => 1
            }]
        },
        from    => {
            mfae => {
                mmrsm => { field => 'source', fkey => 'source' },
                cmf   => { field => 'id', fkey => 'field' }
            }
        },
        where   => {
            '+mmrsm' => { $count_field => $results },
            '+cmf'   => { facet_field => 't' }
        }
    };

    $query->{where}->{'+cmf'}->{field_class} = {'not in' => $ignore}
        if ref($ignore) and @$ignore > 0;

    my $facets = $U->cstorereq("open-ils.cstore.json_query.atomic", $query);

    for my $facet (@$facets) {
        next unless ($facet->{value});
        $data->{$facet->{id}}->{$facet->{value}} += $facet->{count};
    }

    $logger->info("facet compilation: cached with key=$key");

    $cache->put_cache($key, $data, $cache_timeout);
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
    method   => "biblio_mrid_to_modsbatch_batch",
    api_name => "open-ils.search.biblio.metarecord.mods_slim.batch.retrieve"
);

sub biblio_mrid_to_modsbatch_batch {
	my( $self, $client, $mrids) = @_;
	# warn "Performing mrid_to_modsbatch_batch..."; # unconditional warn
	my @mods;
	my $method = $self->method_lookup("open-ils.search.biblio.metarecord.mods_slim.retrieve");
	for my $id (@$mrids) {
		next unless defined $id;
		my ($m) = $method->run($id);
		push @mods, $m;
	}
	return \@mods;
}


foreach (qw /open-ils.search.biblio.metarecord.mods_slim.retrieve
             open-ils.search.biblio.metarecord.mods_slim.retrieve.staff/)
    {
    __PACKAGE__->register_method(
        method    => "biblio_mrid_to_modsbatch",
        api_name  => $_,
        signature => {
            desc   => "Returns the mvr associated with a given metarecod. If none exists, it is created.  "
                    . "As usual, the .staff version of this method will include otherwise hidden records.",
            params => [
                { desc => 'Metarecord ID', type => 'number' },
                { desc => '(Optional) Search filters hash with possible keys: format, org, depth', type => 'object' }
            ],
            return => {
                desc => 'MVR Object, event on error',
            }
        }
    );
}

sub biblio_mrid_to_modsbatch {
	my( $self, $client, $mrid, $args) = @_;

	# warn "Grabbing mvr for $mrid\n";    # unconditional warn

	my ($mr, $evt) = _grab_metarecord($mrid);
	return $evt unless $mr;

	my $mvr = biblio_mrid_check_mvr($self, $client, $mr) ||
              biblio_mrid_make_modsbatch($self, $client, $mr);

	return $mvr unless ref($args);	

	# Here we find the lead record appropriate for the given filters 
	# and use that for the title and author of the metarecord
    my $format = $$args{format};
    my $org    = $$args{org};
    my $depth  = $$args{depth};

	return $mvr unless $format or $org or $depth;

	my $method = "open-ils.storage.ordered.metabib.metarecord.records";
	$method = "$method.staff" if $self->api_name =~ /staff/o; 

	my $rec = $U->storagereq($method, $format, $org, $depth, 1);

	if( my $mods = $U->record_to_mvr($rec) ) {

        $mvr->title( $mods->title );
        $mvr->author($mods->author);
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
    method   => "biblio_mrid_check_mvr",
    api_name => "open-ils.search.biblio.metarecord.mods_slim.check",
    notes    => "Takes a metarecord ID or a metarecord object and returns true "
              . "if the metarecord already has an mvr associated with it."
);

sub biblio_mrid_check_mvr {
	my( $self, $client, $mrid ) = @_;
	my $mr; 

	my $evt;
	if(ref($mrid)) { $mr = $mrid; } 
	else { ($mr, $evt) = _grab_metarecord($mrid); }
	return $evt if $evt;

	# warn "Checking mvr for mr " . $mr->id . "\n";   # unconditional warn

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
    method   => "biblio_mrid_make_modsbatch",
    api_name => "open-ils.search.biblio.metarecord.mods_slim.create",
    notes    => "Takes either a metarecord ID or a metarecord object. "
              . "Forces the creations of an mvr for the given metarecord. "
              . "The created mvr is returned."
);

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

foreach (qw/open-ils.search.biblio.metarecord_to_records
            open-ils.search.biblio.metarecord_to_records.staff/)
{
    __PACKAGE__->register_method(
        method    => "biblio_mrid_to_record_ids",
        api_name  => $_,
        signature => {
            desc   => "Fetch record IDs corresponding to a meta-record ID, with optional search filters. "
                    . "As usual, the .staff version of this method will include otherwise hidden records.",
            params => [
                { desc => 'Metarecord ID', type => 'number' },
                { desc => '(Optional) Search filters hash with possible keys: format, org, depth', type => 'object' }
            ],
            return => {
                desc => 'Results object like {count => $i, ids =>[...]}',
                type => 'object'
            }
            
        }
    );
}

sub biblio_mrid_to_record_ids {
	my( $self, $client, $mrid, $args ) = @_;

    my $format = $$args{format};
    my $org    = $$args{org};
    my $depth  = $$args{depth};

	my $method = "open-ils.storage.ordered.metabib.metarecord.records.atomic";
	$method =~ s/atomic/staff\.atomic/o if $self->api_name =~ /staff/o; 
	my $recs = $U->storagereq($method, $mrid, $format, $org, $depth);

	return { count => scalar(@$recs), ids => $recs };
}


__PACKAGE__->register_method(
    method   => "biblio_record_to_marc_html",
    api_name => "open-ils.search.biblio.record.html"
);

__PACKAGE__->register_method(
    method   => "biblio_record_to_marc_html",
    api_name => "open-ils.search.authority.to_html"
);

# Persistent parsers and setting objects
my $parser = XML::LibXML->new();
my $xslt   = XML::LibXSLT->new();
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
    method    => "format_biblio_record_entry",
    api_name  => "open-ils.search.biblio.record.print",
    signature => {
        desc   => 'Returns a printable version of the specified bib record',
        params => [
            { desc => 'Biblio record entry ID or array of IDs', type => 'number' },
        ],
        return => {
            desc => q/An action_trigger.event object or error event./,
            type => 'object',
        }
    }
);
__PACKAGE__->register_method(
    method    => "format_biblio_record_entry",
    api_name  => "open-ils.search.biblio.record.email",
    signature => {
        desc   => 'Emails an A/T templated version of the specified bib records to the authorized user',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'Biblio record entry ID or array of IDs', type => 'number' },
        ],
        return => {
            desc => q/Undefined on success, otherwise an error event./,
            type => 'object',
        }
    }
);

sub format_biblio_record_entry {
    my($self, $conn, $arg1, $arg2) = @_;

    my $for_print = ($self->api_name =~ /print/);
    my $for_email = ($self->api_name =~ /email/);

    my $e; my $auth; my $bib_id; my $context_org;

    if ($for_print) {
        $bib_id = $arg1;
        $context_org = $arg2 || $U->get_org_tree->id;
        $e = new_editor(xact => 1);
    } elsif ($for_email) {
        $auth = $arg1;
        $bib_id = $arg2;
        $e = new_editor(authtoken => $auth, xact => 1);
        return $e->die_event unless $e->checkauth;
        $context_org = $e->requestor->home_ou;
    }

    my $bib_ids;
    if (ref $bib_id ne 'ARRAY') {
        $bib_ids = [ $bib_id ];
    } else {
        $bib_ids = $bib_id;
    }

    my $bucket = Fieldmapper::container::biblio_record_entry_bucket->new;
    $bucket->btype('temp');
    $bucket->name('format_biblio_record_entry ' . $U->create_uuid_string);
    if ($for_email) {
        $bucket->owner($e->requestor) 
    } else {
        $bucket->owner(1);
    }
    my $bucket_obj = $e->create_container_biblio_record_entry_bucket($bucket);

    for my $id (@$bib_ids) {

        my $bib = $e->retrieve_biblio_record_entry([$id]) or return $e->die_event;

        my $bucket_entry = Fieldmapper::container::biblio_record_entry_bucket_item->new;
        $bucket_entry->target_biblio_record_entry($bib);
        $bucket_entry->bucket($bucket_obj->id);
        $e->create_container_biblio_record_entry_bucket_item($bucket_entry);
    }

    $e->commit;

    if ($for_print) {

        return $U->fire_object_event(undef, 'biblio.format.record_entry.print', [ $bucket ], $context_org);

    } elsif ($for_email) {

        $U->create_events_for_hook('biblio.format.record_entry.email', $bucket, $context_org, undef, undef, 1);
    }

    return undef;
}


__PACKAGE__->register_method(
    method   => "retrieve_all_copy_statuses",
    api_name => "open-ils.search.config.copy_status.retrieve.all"
);

sub retrieve_all_copy_statuses {
	my( $self, $client ) = @_;
	return new_editor()->retrieve_all_config_copy_status();
}


__PACKAGE__->register_method(
    method   => "copy_counts_per_org",
    api_name => "open-ils.search.biblio.copy_counts.retrieve"
);

__PACKAGE__->register_method(
    method   => "copy_counts_per_org",
    api_name => "open-ils.search.biblio.copy_counts.retrieve.staff"
);

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
    method   => "copy_count_summary",
    api_name => "open-ils.search.biblio.copy_counts.summary.retrieve",
    notes    => "returns an array of these: "
              . "[ org_id, callnumber_prefix, callnumber_label, callnumber_suffix, <status1_count>, <status2_count>,...] "
              . "where statusx is a copy status name.  The statuses are sorted by ID.",
);
		

sub copy_count_summary {
	my( $self, $client, $rid, $org, $depth ) = @_;
    $org   ||= 1;
    $depth ||= 0;
    my $data = $U->storagereq(
		'open-ils.storage.biblio.record_entry.status_copy_count.atomic', $rid, $org, $depth );

    return [ sort {
        (($a->[1] ? $a->[1] . ' ' : '') . $a->[2] . ($a->[3] ? ' ' . $a->[3] : ''))
        cmp
        (($b->[1] ? $b->[1] . ' ' : '') . $b->[2] . ($b->[3] ? ' ' . $b->[3] : ''))
    } @$data ];
}

__PACKAGE__->register_method(
    method   => "copy_location_count_summary",
    api_name => "open-ils.search.biblio.copy_location_counts.summary.retrieve",
    notes    => "returns an array of these: "
              . "[ org_id, callnumber_prefix, callnumber_label, callnumber_suffix, copy_location, <status1_count>, <status2_count>,...] "
              . "where statusx is a copy status name.  The statuses are sorted by ID.",
);

sub copy_location_count_summary {
    my( $self, $client, $rid, $org, $depth ) = @_;
    $org   ||= 1;
    $depth ||= 0;
    my $data = $U->storagereq(
		'open-ils.storage.biblio.record_entry.status_copy_location_count.atomic', $rid, $org, $depth );

    return [ sort {
        (($a->[1] ? $a->[1] . ' ' : '') . $a->[2] . ($a->[3] ? ' ' . $a->[3] : ''))
        cmp
        (($b->[1] ? $b->[1] . ' ' : '') . $b->[2] . ($b->[3] ? ' ' . $b->[3] : ''))

        || $a->[4] cmp $b->[4]
    } @$data ];
}

__PACKAGE__->register_method(
    method   => "copy_count_location_summary",
    api_name => "open-ils.search.biblio.copy_counts.location.summary.retrieve",
    notes    => "returns an array of these: "
              . "[ org_id, callnumber_prefix, callnumber_label, callnumber_suffix, <status1_count>, <status2_count>,...] "
              . "where statusx is a copy status name.  The statuses are sorted by ID."
);

sub copy_count_location_summary {
    my( $self, $client, $rid, $org, $depth ) = @_;
    $org   ||= 1;
    $depth ||= 0;
    my $data = $U->storagereq(
        'open-ils.storage.biblio.record_entry.status_copy_location_count.atomic', $rid, $org, $depth );
    return [ sort {
        (($a->[1] ? $a->[1] . ' ' : '') . $a->[2] . ($a->[3] ? ' ' . $a->[3] : ''))
        cmp
        (($b->[1] ? $b->[1] . ' ' : '') . $b->[2] . ($b->[3] ? ' ' . $b->[3] : ''))
    } @$data ];
}


foreach (qw/open-ils.search.biblio.marc
            open-ils.search.biblio.marc.staff/)
{
__PACKAGE__->register_method(
    method    => "marc_search",
    api_name  => $_,
    signature => {
        desc   => 'Fetch biblio IDs based on MARC record criteria.  '
                . 'As usual, the .staff version of the search includes otherwise hidden records',
        params => [
            {
                desc => 'Search hash (required) with possible elements: searches, limit, offset, sort, sort_dir. ' .
                        'See perldoc ' . __PACKAGE__ . ' for more detail.',
                type => 'object'
            },
            {desc => 'limit (optional)',  type => 'number'},
            {desc => 'offset (optional)', type => 'number'}
        ],
        return => {
            desc => 'Results object like: { "count": $i, "ids": [...] }',
            type => 'object'
        }
    }
);
}

=head3 open-ils.search.biblio.marc (arghash, limit, offset)

As elsewhere the arghash is the required argument, and must be a hashref.  The keys are:

    searches: complex query object  (required)
    org_unit: The org ID to focus the search at
    depth   : The org depth     
    limit   : integer search limit      default: 10
    offset  : integer search offset     default:  0
    sort    : What field to sort the results on? [ author | title | pubdate ]
    sort_dir: In what direction do we sort? [ asc | desc ]

Additional keys to refine search criteria:

    audience : Audience
    language : Language (code)
    lit_form : Literary form
    item_form: Item form
    item_type: Item type
    format   : The MARC format

Please note that the specific strings to be used in the "addtional keys" will be entirely
dependent on your loaded data.  

All keys except "searches" are optional.
The "searches" value must be an arrayref of hashref elements, including keys "term" and "restrict".  

For example, an arg hash might look like:

    $arghash = {
        searches => [
            {
                term     => "harry",
                restrict => [
                    {
                        tag => 245,
                        subfield => "a"
                    }
                    # ...
                ]
            }
            # ...
        ],
        org_unit  => 1,
        limit     => 5,
        sort      => "author",
        item_type => "g"
    }

The arghash is eventually passed to the SRF call:
L<open-ils.storage.biblio.full_rec.multi_search[.staff].atomic>

Presently, search uses the cache unconditionally.

=cut

# FIXME: that example above isn't actually tested.
# TODO: docache option?
sub marc_search {
	my( $self, $conn, $args, $limit, $offset, $timeout ) = @_;

	my $method = 'open-ils.storage.biblio.full_rec.multi_search';
	$method .= ".staff" if $self->api_name =~ /staff/;
	$method .= ".atomic";

    $limit  ||= 10;     # FIXME: what about $args->{limit} ?
    $offset ||=  0;     # FIXME: what about $args->{offset} ?

    # allow caller to pass in a call timeout since MARC searches
    # can take longer than the default 60-second timeout.  
    # Default to 2 mins.  Arbitrarily cap at 5 mins.
    $timeout = 120 if !$timeout or $timeout > 300;

	my @search;
	push( @search, ($_ => $$args{$_}) ) for (sort keys %$args);
	my $ckey = $pfx . md5_hex($method . OpenSRF::Utils::JSON->perl2JSON(\@search));

	my $recs = search_cache($ckey, $offset, $limit);

	if(!$recs) {

        my $ses = OpenSRF::AppSession->create('open-ils.storage');
        my $req = $ses->request($method, %$args);
        my $resp = $req->recv($timeout);

        if($resp and $recs = $resp->content) {
			put_cache($ckey, scalar(@$recs), $recs);
			$recs = [ @$recs[$offset..($offset + ($limit - 1))] ];
		} else {
			$recs = [];
		}

        $ses->kill_me;
	}

	my $count = 0;
	$count = $recs->[0]->[2] if $recs->[0] and $recs->[0]->[2];
	my @recs = map { $_->[0] } @$recs;

	return { ids => \@recs, count => $count };
}


foreach my $isbn_method (qw/
    open-ils.search.biblio.isbn
    open-ils.search.biblio.isbn.staff
/) {
__PACKAGE__->register_method(
    method    => "biblio_search_isbn",
    api_name  => $isbn_method,
    signature => {
        desc   => 'Retrieve biblio IDs for a given ISBN. The .staff version of the call includes otherwise hidden hits.',
        params => [
            {desc => 'ISBN', type => 'string'}
        ],
        return => {
            desc => 'Results object like: { "count": $i, "ids": [...] }',
            type => 'object'
        }
    }
);
}

sub biblio_search_isbn { 
	my( $self, $client, $isbn ) = @_;
	$logger->debug("Searching ISBN $isbn");
	# the previous implementation of this method was essentially unlimited,
	# so we will set our limit very high and let multiclass.query provide any
	# actual limit
	# XXX: if making this unlimited is deemed important, we might consider
	# reworking 'open-ils.storage.id_list.biblio.record_entry.search.isbn',
	# which is functionally deprecated at this point, or a custom call to
	# 'open-ils.storage.biblio.multiclass.search_fts'

    my $isbn_method = 'open-ils.search.biblio.multiclass.query';
    if ($self->api_name =~ m/.staff$/) {
        $isbn_method .= '.staff';
    }

	my $method = $self->method_lookup($isbn_method);
	my ($search_result) = $method->run({'limit' => 1000000}, "identifier|isbn:$isbn");
	my @recs = map { $_->[0] } @{$search_result->{'ids'}};
	return { ids => \@recs, count => $search_result->{'count'} };
}

__PACKAGE__->register_method(
    method   => "biblio_search_isbn_batch",
    api_name => "open-ils.search.biblio.isbn_list",
);

# XXX: see biblio_search_isbn() for note concerning 'limit'
sub biblio_search_isbn_batch { 
	my( $self, $client, $isbn_list ) = @_;
	$logger->debug("Searching ISBNs @$isbn_list");
	my @recs = (); my %rec_set = ();
	my $method = $self->method_lookup('open-ils.search.biblio.multiclass.query');
	foreach my $isbn ( @$isbn_list ) {
		my ($search_result) = $method->run({'limit' => 1000000}, "identifier|isbn:$isbn");
		my @recs_subset = map { $_->[0] } @{$search_result->{'ids'}};
		foreach my $rec (@recs_subset) {
			if (! $rec_set{ $rec }) {
				$rec_set{ $rec } = 1;
				push @recs, $rec;
			}
		}
	}
	return { ids => \@recs, count => scalar(@recs) };
}

foreach my $issn_method (qw/
    open-ils.search.biblio.issn
    open-ils.search.biblio.issn.staff
/) {
__PACKAGE__->register_method(
    method   => "biblio_search_issn",
    api_name => $issn_method,
    signature => {
        desc   => 'Retrieve biblio IDs for a given ISSN',
        params => [
            {desc => 'ISBN', type => 'string'}
        ],
        return => {
            desc => 'Results object like: { "count": $i, "ids": [...] }',
            type => 'object'
        }
    }
);
}

sub biblio_search_issn { 
	my( $self, $client, $issn ) = @_;
	$logger->debug("Searching ISSN $issn");
	# the previous implementation of this method was essentially unlimited,
	# so we will set our limit very high and let multiclass.query provide any
	# actual limit
	# XXX: if making this unlimited is deemed important, we might consider
	# reworking 'open-ils.storage.id_list.biblio.record_entry.search.issn',
	# which is functionally deprecated at this point, or a custom call to
	# 'open-ils.storage.biblio.multiclass.search_fts'

    my $issn_method = 'open-ils.search.biblio.multiclass.query';
    if ($self->api_name =~ m/.staff$/) {
        $issn_method .= '.staff';
    }

	my $method = $self->method_lookup($issn_method);
	my ($search_result) = $method->run({'limit' => 1000000}, "identifier|issn:$issn");
	my @recs = map { $_->[0] } @{$search_result->{'ids'}};
	return { ids => \@recs, count => $search_result->{'count'} };
}


__PACKAGE__->register_method(
    method    => "fetch_mods_by_copy",
    api_name  => "open-ils.search.biblio.mods_from_copy",
    argc      => 1,
    signature => {
        desc    => 'Retrieve MODS record given an attached copy ID',
        params  => [
            { desc => 'Copy ID', type => 'number' }
        ],
        returns => {
            desc => 'MODS record, event on error or uncataloged item'
        }
    }
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
    method   => "cn_browse",
    api_name => "open-ils.search.callnumber.browse.target",
    notes    => "Starts a callnumber browse"
);

__PACKAGE__->register_method(
    method   => "cn_browse",
    api_name => "open-ils.search.callnumber.browse.page_up",
    notes    => "Returns the previous page of callnumbers",
);

__PACKAGE__->register_method(
    method   => "cn_browse",
    api_name => "open-ils.search.callnumber.browse.page_down",
    notes    => "Returns the next page of callnumbers",
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
    method        => "fetch_cn",
    api_name      => "open-ils.search.callnumber.retrieve",
    authoritative => 1,
    notes         => "retrieves a callnumber based on ID",
);

sub fetch_cn {
	my( $self, $client, $id ) = @_;

	my $e = new_editor();
	my( $cn, $evt ) = $apputils->fetch_callnumber( $id, 0, $e );
	return $evt if $evt;
	return $cn;
}

__PACKAGE__->register_method(
    method        => "fetch_fleshed_cn",
    api_name      => "open-ils.search.callnumber.fleshed.retrieve",
    authoritative => 1,
    notes         => "retrieves a callnumber based on ID, fleshing prefix, suffix, and label_class",
);

sub fetch_fleshed_cn {
	my( $self, $client, $id ) = @_;

	my $e = new_editor();
	my( $cn, $evt ) = $apputils->fetch_callnumber( $id, 1, $e );
	return $evt if $evt;
	return $cn;
}


__PACKAGE__->register_method(
    method    => "fetch_copy_by_cn",
    api_name  => 'open-ils.search.copies_by_call_number.retrieve',
    signature => q/
		Returns an array of copy ID's by callnumber ID
		@param cnid The callnumber ID
		@return An array of copy IDs
	/
);

sub fetch_copy_by_cn {
	my( $self, $conn, $cnid ) = @_;
	return $U->cstorereq(
		'open-ils.cstore.direct.asset.copy.id_list.atomic', 
		{ call_number => $cnid, deleted => 'f' } );
}

__PACKAGE__->register_method(
    method    => 'fetch_cn_by_info',
    api_name  => 'open-ils.search.call_number.retrieve_by_info',
    signature => q/
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



__PACKAGE__->register_method(
    method   => 'bib_extras',
    api_name => 'open-ils.search.biblio.lit_form_map.retrieve.all',
    ctype => 'lit_form'
);
__PACKAGE__->register_method(
    method   => 'bib_extras',
    api_name => 'open-ils.search.biblio.item_form_map.retrieve.all',
    ctype => 'item_form'
);
__PACKAGE__->register_method(
    method   => 'bib_extras',
    api_name => 'open-ils.search.biblio.item_type_map.retrieve.all',
    ctype => 'item_type',
);
__PACKAGE__->register_method(
    method   => 'bib_extras',
    api_name => 'open-ils.search.biblio.bib_level_map.retrieve.all',
    ctype => 'bib_level'
);
__PACKAGE__->register_method(
    method   => 'bib_extras',
    api_name => 'open-ils.search.biblio.audience_map.retrieve.all',
    ctype => 'audience'
);

sub bib_extras {
	my $self = shift;
    $logger->warn("deprecation warning: " .$self->api_name);

	my $e = new_editor();

    my $ctype = $self->{ctype};
    my $ccvms = $e->search_config_coded_value_map({ctype => $ctype});

    my @objs;
    for my $ccvm (@$ccvms) {
        my $obj = "Fieldmapper::config::${ctype}_map"->new;
        $obj->value($ccvm->value);
        $obj->code($ccvm->code);
        $obj->description($ccvm->description) if $obj->can('description');
        push(@objs, $obj);
    }

    return \@objs;
}



__PACKAGE__->register_method(
    method    => 'fetch_slim_record',
    api_name  => 'open-ils.search.biblio.record_entry.slim.retrieve',
    signature => {
        desc   => "Retrieves one or more biblio.record_entry without the attached marcxml",
        params => [
            { desc => 'Array of Record IDs', type => 'array' }
        ],
        return => { 
            desc => 'Array of biblio records, event on error'
        }
    }
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
    method    => 'rec_hold_parts',
    api_name  => 'open-ils.search.biblio.record_hold_parts',
    signature => q/
       Returns a list of {label :foo, id : bar} objects for viable monograph parts for a given record
	/
);

sub rec_hold_parts {
	my( $self, $conn, $args ) = @_;

    my $rec        = $$args{record};
    my $mrec       = $$args{metarecord};
    my $pickup_lib = $$args{pickup_lib};
    my $e = new_editor();

    my $query = {
        select => {bmp => ['id', 'label']},
        from => 'bmp',
        where => {
            id => {
                in => {
                    select => {'acpm' => ['part']},
                    from => {acpm => {acp => {join => {acn => {join => 'bre'}}}}},
                    where => {
                        '+acp' => {'deleted' => 'f'},
                        '+bre' => {id => $rec}
                    },
                    distinct => 1,
                }
            }
        },
        order_by =>[{class=>'bmp', field=>'label_sortkey'}]
    };

    if(defined $pickup_lib) {
        my $hard_boundary = $U->ou_ancestor_setting_value($pickup_lib, OILS_SETTING_HOLD_HARD_BOUNDARY);
        if($hard_boundary) {
            my $orgs = $e->json_query({from => ['actor.org_unit_descendants' => $pickup_lib, $hard_boundary]});
            $query->{where}->{'+acp'}->{circ_lib} = [ map { $_->{id} } @$orgs ];
        }
    }

    return $e->json_query($query);
}




__PACKAGE__->register_method(
    method    => 'rec_to_mr_rec_descriptors',
    api_name  => 'open-ils.search.metabib.record_to_descriptors',
    signature => q/
		specialized method...
		Given a biblio record id or a metarecord id, 
		this returns a list of metabib.record_descriptor
		objects that live within the same metarecord
		@param args Object of args including:
	/
);

sub rec_to_mr_rec_descriptors {
	my( $self, $conn, $args ) = @_;

    my $rec        = $$args{record};
    my $mrec       = $$args{metarecord};
    my $item_forms = $$args{item_forms};
    my $item_types = $$args{item_types};
    my $item_lang  = $$args{item_lang};
    my $pickup_lib = $$args{pickup_lib};

    my $hard_boundary = $U->ou_ancestor_setting_value($pickup_lib, OILS_SETTING_HOLD_HARD_BOUNDARY) if (defined $pickup_lib);

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
	$search->{item_lang} = $item_lang  if $item_lang;

	my $desc = $e->search_metabib_record_descriptor($search);

	my $query = {
		distinct => 1,
		select   => { 'bre' => ['id'] },
		from	 => {
			'bre' => {
				'acn' => {
					'join' => {
						'acp' => {"join" => {"acpl" => {}, "ccs" => {}}}
					  }
				  }
			 }
		},
		where => {
			'+bre' => { id => \@recs },
			'+acp' => {
				holdable => 't',
				deleted  => 'f'
			},
			"+ccs" => { holdable => 't' },
			"+acpl" => { holdable => 't' }
		}
	};

	if ($hard_boundary) { # 0 (or "top") is the same as no setting
		my $orgs = $e->json_query(
			{ from => [ 'actor.org_unit_descendants' => $pickup_lib, $hard_boundary ] }
		) or return $e->die_event;

		$query->{where}->{"+acp"}->{circ_lib} = [ map { $_->{id} } @$orgs ];
	}

	my $good_records = $e->json_query($query) or return $e->die_event;

	my @keep;
	for my $d (@$desc) {
		if ( grep { $d->record == $_->{id} } @$good_records ) {
			push @keep, $d;
		}
	}

	$desc = \@keep;

	return { metarecord => $mrec, descriptors => $desc };
}


__PACKAGE__->register_method(
    method   => 'fetch_age_protect',
    api_name => 'open-ils.search.copy.age_protect.retrieve.all',
);

sub fetch_age_protect {
	return new_editor()->retrieve_all_config_rule_age_hold_protect();
}


__PACKAGE__->register_method(
    method   => 'copies_by_cn_label',
    api_name => 'open-ils.search.asset.copy.retrieve_by_cn_label',
);

__PACKAGE__->register_method(
    method   => 'copies_by_cn_label',
    api_name => 'open-ils.search.asset.copy.retrieve_by_cn_label.staff',
);

sub copies_by_cn_label {
	my( $self, $conn, $record, $cn_parts, $circ_lib ) = @_;
	my $e = new_editor();
    my $cnp_id = $cn_parts->[0] eq '' ? -1 : $e->search_asset_call_number_prefix({label => $cn_parts->[0]}, {idlist=>1})->[0];
    my $cns_id = $cn_parts->[2] eq '' ? -1 : $e->search_asset_call_number_suffix({label => $cn_parts->[2]}, {idlist=>1})->[0];
	my $cns = $e->search_asset_call_number({record => $record, prefix => $cnp_id, label => $cn_parts->[1], suffix => $cns_id, deleted => 'f'}, {idlist=>1});
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

