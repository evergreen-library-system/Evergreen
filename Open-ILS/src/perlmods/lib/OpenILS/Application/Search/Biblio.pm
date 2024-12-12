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
use Email::Send;
use Email::MIME;

use OpenSRF::Utils::Logger qw/:logger/;

use Time::HiRes qw(time sleep);
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
my $max_concurrent_search;

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

    if(ref($id) and ref($id) eq 'ARRAY') {
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

__PACKAGE__->register_method(
    method   => "record_id_to_copy_count",
    api_name => "open-ils.search.biblio.record.copy_count.lasso",
    signature => {
        desc => q/Returns a copy summary for the given record for the context library group/,
        params => [
            {desc => 'Context org unit id', type => 'number'},
            {desc => 'Record ID', type => 'number'},
            {desc => 'Library Group ID', type => 'number'}
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
    api_name      => "open-ils.search.biblio.record.copy_count.staff.lasso",
    authoritative => 1,
    signature => {
        desc => q/Returns a copy summary for the given record for the context library group/,
        params => [
            {desc => 'Context org unit id', type => 'number'},
            {desc => 'Record ID', type => 'number'},
            {desc => 'Library Group ID', type => 'number'}
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
    api_name => "open-ils.search.biblio.metarecord.copy_count.lasso",
    signature => {
        desc => q/Returns a copy summary for the given record for the context library group/,
        params => [
            {desc => 'Context org unit id', type => 'number'},
            {desc => 'Record ID', type => 'number'},
            {desc => 'Library Group ID', type => 'number'}
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
    api_name => "open-ils.search.biblio.metarecord.copy_count.staff.lasso",
    signature => {
        desc => q/Returns a copy summary for the given record for the context library group/,
        params => [
            {desc => 'Context org unit id', type => 'number'},
            {desc => 'Record ID', type => 'number'},
            {desc => 'Library Group ID', type => 'number'}
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
    my( $self, $client, $org_id, $record_id, $lasso_id ) = @_;

    return [] unless $record_id;

    my $key = $self->api_name =~ /metarecord/ ? 'metarecord' : 'record';
    my $staff = $self->api_name =~ /staff/ ? 't' : 'f';

    my $args;
    if ($lasso_id) {
        my $scope = $self->api_name =~ /staff/ ? 'staff' : 'opac';
        $args = ['asset.' . $scope . '_lasso_' . $key  . '_copy_count_sum' => $lasso_id => $record_id];
    } else {
        $args = ['asset.' . $key  . '_copy_count' => $org_id => $record_id => $staff];
    }
    my $data = $U->cstorereq(
        "open-ils.cstore.json_query.atomic",
        { from => $args }
    );

    my @count;
    for my $d ( @$data ) { # fix up the key name change required by stored-proc version
        $$d{count} = delete $$d{visible};
        push @count, $d;
    }

    return [ sort { $a->{depth} <=> $b->{depth} } @count ];
}


__PACKAGE__->register_method(
    method => 'copy_total',
    api_name => 'open-ils.search.biblio.record.copy_total',
    signature => {
        desc => 'returns a total of all public items on a record at the specified orgs and library groups',
        params => [
            {desc => 'Record ID', type => 'number'},
            {desc => 'Org unit IDs', type => 'arrayref'},
            {desc => 'Org unit depth', type => 'number'},
            {desc => 'Library group IDs', type => 'arrayref'},
        ],
        return => {
            desc => 'total of all public items on the record',
            type => 'bool'
        }
    }
);

__PACKAGE__->register_method(
    method => 'copy_total',
    api_name => 'open-ils.search.biblio.record.copy_total.staff',
    signature => {
        desc => 'returns a total of all staff-visible items on a record at the specified orgs and library groups',
        params => [
            {desc => 'Record ID', type => 'number'},
            {desc => 'Org unit IDs', type => 'arrayref'},
            {desc => 'Org unit depth', type => 'number'},
            {desc => 'Library group IDs', type => 'arrayref'},
        ],
        return => {
            desc => 'total of all staff-visible items on the record',
            type => 'bool'
        }
    }
);

sub copy_total {
    my ($self, $client, $record_id, $org_unit_ids, $org_unit_depth, $library_group_ids) = @_;
    my $total_function = $self->api_name =~ /staff/ ? 'asset.staff_copy_total' : 'asset.opac_copy_total';
    return new_editor->json_query(
        {from => [$total_function =>
            $record_id,
            '{' . join(',', @$org_unit_ids) . '}',
            $org_unit_depth,
            '{' . join(',', @$library_group_ids) . '}']}
    )->[0]->{$total_function};
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

__PACKAGE__->register_method(
    method   => "biblio_search_tcn_batch",
    api_name => "open-ils.search.biblio.tcn.batch",
    argc     => 2,
    signature => {
        desc   => "Retrieve related record ID(s) given a list of TCNs",
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Array of TCNs', type => 'array' },
            { desc => 'Flag indicating to include deleted records', type => 'string' }
        ],
        return => {
            desc => 'Results object like: { "successful": [ { "tcn": $tcn, "ids": [...] }, ... ], "failed": [ $tcn, ... ] }',
            type => 'object'
        }
    }
);

sub biblio_search_tcn_batch {
    my( $self, $client, $auth, $tcns, $include_deleted ) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $results = { successful => [], failed => [] };

    foreach my $tcn (@$tcns) {
        $tcn =~ s/^\s+|\s+$//og;
        my $search = {tcn_value => $tcn};
        $search->{deleted} = 'f' unless $include_deleted;
        my $recs = $e->search_biblio_record_entry( $search, {idlist => 1} );

        if (@$recs) {
            push @{$results->{successful}}, { tcn => $tcn, ids => $recs };
        } else {
            push @{$results->{failed}}, $tcn;
        }
    }

    return $results;
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
    method  => "biblio_id_to_uris",
    api_name=> "open-ils.search.asset.uri.retrieve_by_bib",
    argc    => 2, 
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
                flesh               => 1,
                flesh_fields    => { 
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
 lang - limit by language (specify multiple langs with lang:l1 lang:l2 ...)
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
    # arghash only really supports limit/offset anymore
    my($self, $conn, $arghash, $query, $docache, $phys_loc) = @_;

    if ($query) {
        $query =~ s/\+/ /go;
        $query =~ s/^\s+//go;
        $query =~ s/\s+/ /go;
        $arghash->{query} = $query
    }

    $logger->debug("initial search query => $query") if $query;

    (my $method = $self->api_name) =~ s/\.query/.staged/o;
    return $self->method_lookup($method)->dispatch($arghash, $docache, $phys_loc);

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
    $$searchhash{searches}{'identifier|upc'}{term} = $$args{search}{upc} if $$args{search}{upc};

    $$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{tcn}       if $$args{search}{tcn};
    $$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{publisher} if $$args{search}{publisher};
    $$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{pubdate}   if $$args{search}{pubdate};
    $$searchhash{searches}{keyword}{term} .= join ' ', $$searchhash{searches}{keyword}{term}, $$args{search}{item_type} if $$args{search}{item_type};

    my $method = 'open-ils.search.biblio.multiclass.staged';
    $method .= '.staff' if $self->api_name =~ /staff$/;

    my ($list) = $self->method_lookup($method)->run( $searchhash );

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
    method    => 'staff_location_groups_with_lassos',
    api_name  => 'open-ils.search.staff.location_groups_with_lassos',
);
sub staff_location_groups_with_lassos {
    my $flag = new_editor()->retrieve_config_global_flag('staff.search.shelving_location_groups_with_lassos');
    return $flag ? $flag->enabled eq 't' : 0;
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

my $estimation_strategy;
sub staged_search {
    my($self, $conn, $search_hash, $docache, $phys_loc) = @_;

    my $e = new_editor();
    if (!$max_concurrent_search) {
        my $mcs = $e->retrieve_config_global_flag('opac.max_concurrent_search.query');
        $max_concurrent_search = ($mcs and $mcs->enabled eq 't') ? $mcs->value : 20;
    }

    $phys_loc ||= $U->get_org_tree->id;

    my $IAmMetabib = ($self->api_name =~ /metabib/) ? 1 : 0;

    my $method = $IAmMetabib?
        'open-ils.storage.metabib.multiclass.staged.search_fts':
        'open-ils.storage.biblio.multiclass.staged.search_fts';

    $method .= '.staff' if $self->api_name =~ /staff$/;
    $method .= '.atomic';
                
    if (!$search_hash->{query}) {
        return {count => 0} unless (
            $search_hash and 
            $search_hash->{searches} and 
            int(scalar( keys %{$search_hash->{searches}} )));
    }

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
    unless ($estimation_strategy) {
        $estimation_strategy = OpenSRF::Utils::SettingsClient
            ->new
            ->config_value(
                apps => 'open-ils.search', app_settings => 'estimation_strategy'
            ) || 'inclusion';
    }
    $search_hash->{estimation_strategy} = $estimation_strategy;

    # pull any existing results from the cache
    my $key = search_cache_key($method, $search_hash);
    my $facet_key = $key.'_facets';

    # Let the world know that there is at least one backend that will be searching
    my $counter_key = $key.'_counter';
    $cache->get_cache($counter_key) || $cache->{memcache}->add($counter_key, 0, $cache_timeout);
    my $search_peers = $cache->{memcache}->incr($counter_key);

    # If the world tells us that there are more than we want to allow, we stop.
    if ($search_peers > $max_concurrent_search) {
        $logger->warn("Too many concurrent searches per $counter_key: $search_peers");
        $cache->{memcache}->decr($counter_key);
        return OpenILS::Event->new('BAD_PARAMS')
    }

    my $cache_data = $cache->get_cache($key) || {};

    # First, we want to make sure that someone else isn't currently trying to perform exactly
    # this same search.  The point is to allow just one instance of a search to fill the needs
    # of all concurrent, identical searches.  This will avoid spammy searches killing the
    # database without requiring admins to start locking some IP addresses out entirely.
    #
    # There's still a tiny race condition where 2 might run, but without sigificantly more code
    # and complexity, this is close to the best we can do.

    if ($cache_data->{running}) { # someone is already doing the search...
        my $stop_looping = time() + $cache_timeout;
        while ( sleep(1) and time() < $stop_looping ) { # sleep for a second ... maybe they'll finish
            $cache_data = $cache->get_cache($key) || {};
            last if (!$cache_data->{running});
        }
    } elsif (!$cache_data->{0}) { # we're the first ... let's give it a try
        $cache->put_cache($key, { running => $$ }, $cache_timeout / 3);
    }

    # keep retrieving results until we find enough to 
    # fulfill the user-specified limit and offset
    my $all_results = [];
    my $page; # current superpage
    my $current_page_summary = {};
    my $global_summary = {checked => 0, visible => 0, excluded => 0, deleted => 0, total => 0};
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
            $search_hash->{return_query} = $page == 0 ? 1 : 0;

            my $start = time;
            $results = $U->storagereq($method, %$search_hash);
            $search_duration = time - $start;
            $summary = shift(@$results) if $results;

            unless($summary) {
                $logger->info("search timed out: duration=$search_duration: params=".
                    OpenSRF::Utils::JSON->perl2JSON($search_hash));
                $cache->{memcache}->decr($counter_key);
                return {count => 0};
            }

            $logger->info("staged search: DB call took $search_duration seconds and returned ".scalar(@$results)." rows, including summary");

            # Create backwards-compatible result structures
            if($IAmMetabib) {
                $results = [map {[$_->{id}, $_->{badges}, $_->{popularity}, $_->{rel}, $_->{record}]} @$results];
            } else {
                $results = [map {[$_->{id}, $_->{badges}, $_->{popularity}]} @$results];
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

        if ($page == 0) { # all summaries are the same, just get the first
            for (keys %$summary) {
                $global_summary->{$_} = $summary->{$_};
            }
        }

        # we've found all the possible hits
        last if $current_count == $summary->{visible};

        # we've found enough results to satisfy the requested limit/offset
        last if $current_count >= ($user_limit + $user_offset);

        # we've scanned all possible hits
        last if($summary->{checked} < $superpage_size);
    }

    # Let other backends grab our data now that we're done, and flush the key if we're the last one.
    $cache_data = $cache->get_cache($key);
    if ($$cache_data{running} and $$cache_data{running} == $$) {
        delete $$cache_data{running};
        $cache->put_cache($key, $cache_data, $cache_timeout);
    }

    my ($class, $term, $field_list) = one_class_multi_term($global_summary->{query_struct});
    if ($class and $term) { # we meet the current "can suggest" criteria, check for suggestions!
        my $editor = new_editor();
        my $class_settings = $editor->retrieve_config_metabib_class($class);
        $field_list ||= [];

        my $term_count = split(/\s+/, $term); # count of words in the search

        # longest search, in words, we will suggest for. default = 3
        my $max_terms = $editor->search_config_global_flag({name=>'search.max_suggestion_search_terms',enabled=>'t'})->[0];
        $max_terms = $max_terms ? $max_terms->value : 3;

        if ( # search did not provide enough hits and settings
             # for this class want more than 0 suggestions
             # and there are not too many words in the search
            $global_summary->{visible} <= $class_settings->low_result_threshold
            and $class_settings->max_suggestions != 0
            and $term_count <= $max_terms
        ) {
            my $suggestion_verbosity = $class_settings->symspell_suggestion_verbosity;
            if ($class_settings->max_suggestions == -1) { # special value that means "only best suggestion, and not always"
                $class_settings->max_suggestions(1);
                $suggestion_verbosity = 0;
            }

            my $suggs = $editor->json_query({
                from  => [
                    'search.symspell_suggest',
                        $term, $class, '{'.join($field_list).'}',
                        undef, # max edit distance per word, just get the database setting
                        $suggestion_verbosity
                ]
            });

            @$suggs = sort {
                $$a{lev_distance} <=> $$b{lev_distance}
                || (
                    $$b{pg_trgm_sim} * $class_settings->pg_trgm_weight
                    + $$b{soundex_sim} * $class_settings->soundex_weight
                    + $$b{qwerty_kb_match} * $class_settings->keyboard_distance_weight
                        <=>
                    $$a{pg_trgm_sim} * $class_settings->pg_trgm_weight
                    + $$a{soundex_sim} * $class_settings->soundex_weight
                    + $$a{qwerty_kb_match} * $class_settings->keyboard_distance_weight
                )
                || abs($$b{suggestion_count}) <=> abs($$a{suggestion_count})
            } grep  { $$_{lev_distance} != 0 || $$_{suggestion_count} < 0 } @$suggs;

            if (@$suggs) {
                $global_summary->{suggestions}{'one_class_multi_term'} = {
                    class       => $class,
                    term        => $term,
                    suggestions  => [ splice @$suggs, 0, $class_settings->max_suggestions ]
                };
            }
        }
    }

    my @results = grep {defined $_} @$all_results[$user_offset..($user_offset + $user_limit - 1)];

    $conn->respond_complete(
        {
            global_summary    => $global_summary,
            count             => $global_summary->{visible},
            core_limit        => $search_hash->{core_limit},
            superpage         => $page,
            superpage_size    => $search_hash->{check_limit},
            superpage_summary => $current_page_summary,
            facet_key         => $facet_key,
            ids               => \@results
        }
    );
    $cache->{memcache}->decr($counter_key);

    $logger->info("Completed canonicalized search is: $$global_summary{canonicalized_query}");

    return cache_facets($facet_key, $new_ids, $IAmMetabib, $ignore_facet_classes) if $docache;
}

sub one_class_multi_term {
    my $qstruct = shift;
    my $fields = shift;
    my $node = $$qstruct{children};

    my $class = undef;
    my $term = '';
    if ($fields) {
        if ($$node{fields} and @{$$node{fields}} > 0) {
            return (undef,undef,undef) if (join(',', @{$$node{fields}}) ne join(',', @$fields));
        }
    } elsif ($$node{fields}) {
        $fields = [ @{$$node{fields}} ];
    }


    # may relax this...
    return (undef,undef,undef) if ($$node{'|'}
        # or ($$node{modifiers} and @{$$node{modifiers}} > 0)
        # or ($$node{filters} and @{$$node{filters}} > 0)
    );

    for my $kid (@{$$node{'&'}}) {
        my ($subclass, $subterm);
        if ($$kid{type} eq 'query_plan') {
            ($subclass, $subterm) = one_class_multi_term($kid, $fields);
            return (undef,undef,undef) if ($class and $subclass and $class ne $subclass);
            $class = $subclass;
            $term .= ' ' if $term;
            $term .= $subterm if $subterm;
        } elsif ($$kid{type} eq 'node') {
            $subclass = $$kid{class};
            return (undef,undef,undef) if ($class and $subclass and $class ne $subclass);
            $class = $subclass;
            ($subclass, $subterm) = one_class_multi_term($kid, $fields);
            return (undef,undef,undef) if ($subclass and $class ne $subclass);
            $term .= ' ' if $term;
            $term .= $subterm if $subterm;
        } elsif ($$kid{type} eq 'atom') {
            $term .= ' ' if $term;
            if ($$kid{content} !~ /\s+/ and $$kid{prefix} =~ /^-/) {
                # only quote negated multi-word phrases, not negated single words
                $$kid{prefix} = '-';
                $$kid{suffix} = '';
            }
            $term .= $$kid{prefix}.$$kid{content}.$$kid{suffix};
        }
    }

    return ($class, $term, $fields);
}

sub fetch_display_fields {
    my $self = shift;
    my $conn = shift;
    my $highlight_map = shift;
    my @records = @_;

    unless (@records) {
        $conn->respond_complete;
        return;
    }

    my $e = new_editor();
    my $fleshed = 0;
    my %df_cache;

    if ($self->api_name =~ /fleshed$/) {
        $fleshed++;
        %df_cache = map {
            ($_->id => {%{$_->to_bare_hash}{qw/id field_class name label search_field browse_field facet_field display_field restrict/}})
        } @{ $e->retrieve_all_config_metabib_field };
    }

    for my $record ( @records ) {
        next unless ($record && $highlight_map);
        my $hl = $e->json_query({from => ['search.highlight_display_fields', $record, $highlight_map]});
        $hl = [ map { $$_{field} = $df_cache{$$_{field}}; $_ } @$hl ] if $fleshed;
        $conn->respond( $hl );
    }

    return undef;
}
__PACKAGE__->register_method(
    method    => 'fetch_display_fields',
    api_name  => 'open-ils.search.fetch.metabib.display_field.highlight',
    stream   => 1
);

__PACKAGE__->register_method(
    method    => 'fetch_display_fields',
    api_name  => 'open-ils.search.fetch.metabib.display_field.highlight.fleshed',
    stream   => 1
);


sub tag_circulated_records {
    my ($auth, $results, $metabib) = @_;
    my $e = new_editor(authtoken => $auth);
    return $results unless $e->checkauth;

    my $query = {
        select   => { acn => [{ column => 'record', alias => 'tagme' }] }, 
        from     => { auch => { acp => { join => 'acn' }} }, 
        where    => { usr => $e->requestor->id },
        distinct => 1
    };

    if ($metabib) {
        $query = {
            select   => { mmrsm => [{ column => 'metarecord', alias => 'tagme' }] },
            from     => 'mmrsm',
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

    eval {
        local $SIG{ALRM} = sub {die};
        alarm(10); # we'll sleep for as much as 10s
        do {
            die if $cache->get_cache($key . '_COMPLETE');
        } while (sleep(0.05));
        alarm(0);
    };
    alarm(0);

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

    my $facets_function = $metabib ? 'search.facets_for_metarecord_set'
                                   : 'search.facets_for_record_set';
    my $results_str = '{' . join(',', @$results) . '}';
    my $ignore_str = ref($ignore) ? '{' . join(',', @$ignore) . '}'
                                  : '{}';
    my $query = {   
        from => [ $facets_function, $ignore_str, $results_str ]
    };

    my $facets = OpenILS::Utils::CStoreEditor->new->json_query($query, {substream => 1});

    for my $facet (@$facets) {
        next unless ($facet->{value});
        $data->{$facet->{id}}->{$facet->{value}} += $facet->{count};
    }

    $logger->info("facet compilation: cached with key=$key");

    $cache->put_cache($key, $data, $cache_timeout);
    $cache->put_cache($key.'_COMPLETE', 1, $cache_timeout);
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
        ($summary->{estimated_hit_count} || "none") .
        ", visible=" . ($summary->{visible} || "none")
    );

    $cache->put_cache($key, $data, $cache_timeout);
}

sub search_cache {

    my $key     = shift;
    my $offset  = shift;
    my $limit   = shift;
    my $start   = $offset;
    my $end     = $offset + $limit - 1;

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
    method    => "send_event_email_output",
    api_name  => "open-ils.search.biblio.record.email.send_output",
);
sub send_event_email_output {
    my($self, $client, $auth, $event_id, $capkey, $capanswer) = @_;
    return undef unless $event_id;

    my $captcha_pass = 0;
    my $real_answer;
    if ($capkey) {
        $real_answer = $cache->get_cache(md5_hex($capkey));
        $captcha_pass++ if ($real_answer eq $capanswer);
    }

    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $captcha_pass || $e->checkauth;

    my $event = $e->retrieve_action_trigger_event([$event_id,{flesh => 1, flesh_fields => { atev => ['template_output']}}]);
    return undef unless ($event and $event->template_output);

    my $smtp = OpenSRF::Utils::SettingsClient
        ->new
        ->config_value('email_notify', 'smtp_server');

    my $sender = Email::Send->new({mailer => 'SMTP'});
    $sender->mailer_args([Host => $smtp]);

    my $stat;
    my $err;

    my $email = _create_mime_email($event->template_output->data);

    try {
        $stat = $sender->send($email);
    } catch Error with {
        $err = $stat = shift;
        $logger->error("send_event_email_output: Email failed with error: $err");
    };

    if( !$err and $stat and $stat->type eq 'success' ) {
        $logger->info("send_event_email_output: successfully sent email");
        return 1;
    } else {
        $logger->warn("send_event_email_output: unable to send email: ".Dumper($stat));
        return 0;
    }
}

sub _create_mime_email {
    my $template_output = shift;
    my $email = Email::MIME->new($template_output);
    for my $hfield (qw/From To Bcc Cc Reply-To Sender/) {
        my @headers = $email->header($hfield);
        $email->header_str_set($hfield => join(',', @headers)) if ($headers[0]);
    }

    my @headers = $email->header('Subject');
    $email->header_str_set('Subject' => $headers[0]) if ($headers[0]);

    $email->header_set('MIME-Version' => '1.0');
    $email->header_set('Content-Type' => "text/plain; charset=UTF-8");
    $email->header_set('Content-Transfer-Encoding' => '8bit');
    return $email;
}

__PACKAGE__->register_method(
    method    => "format_biblio_record_entry",
    api_name  => "open-ils.search.biblio.record.print.preview",
);

__PACKAGE__->register_method(
    method    => "format_biblio_record_entry",
    api_name  => "open-ils.search.biblio.record.email.preview",
);

__PACKAGE__->register_method(
    method    => "format_biblio_record_entry",
    api_name  => "open-ils.search.biblio.record.print",
    signature => {
        desc   => 'Returns a printable version of the specified bib record',
        params => [
            { desc => 'Biblio record entry ID or array of IDs', type => 'number' },
            { desc => 'Context library for holdings, if applicable', type => 'number' },
            { desc => 'Sort order, if applicable', type => 'string' },
            { desc => 'Sort direction, if applicable', type => 'string' },
            { desc => 'Definition Group Member id', type => 'number' },
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
            { desc => 'Authentication token', type => 'string'},
            { desc => 'Biblio record entry ID or array of IDs', type => 'number' },
            { desc => 'Context library for holdings, if applicable', type => 'number' },
            { desc => 'Sort order, if applicable', type => 'string' },
            { desc => 'Sort direction, if applicable', type => 'string' },
            { desc => 'Definition Group Member id', type => 'number' },
            { desc => 'Whether to bypass auth due to captcha', type => 'bool' },
            { desc => 'Email address, if none for the user', type => 'string' },
            { desc => 'Subject, if customized', type => 'string' },
        ],
        return => {
            desc => q/Undefined on success, otherwise an error event./,
            type => 'object',
        }
    }
);

sub format_biblio_record_entry {
    my ($self, $conn) = splice @_, 0, 2;

    my $for_print = ($self->api_name =~ /print/);
    my $for_email = ($self->api_name =~ /email/);
    my $preview = ($self->api_name =~ /preview/);

    my ($auth, $captcha_pass, $email, $subject);
    if ($for_email) {
        $auth = shift @_;
        if (@_ > 5) { # the stuff below is included in the params, safe to splice
            ($captcha_pass, $email, $subject) = splice @_, -3, 3;
        }
    }
    my ($bib_id, $holdings_context_org, $bib_sort, $sort_dir, $group_member) = @_;
    $holdings_context_org ||= $U->get_org_tree->id;
    $bib_sort ||= 'author';
    $sort_dir ||= 'ascending';

    my $e; my $event_context_org; my $type = 'brief';

    if ($for_print) {
        $event_context_org = $holdings_context_org;
        $e = new_editor(xact => 1);
    } elsif ($for_email) {
        $e = new_editor(authtoken => $auth, xact => 1);
        return $e->die_event unless $captcha_pass || $e->checkauth;
        $event_context_org = $e->requestor ? $e->requestor->home_ou : $holdings_context_org;
        $email ||= $e->requestor ? $e->requestor->email : '';
    }

    if ($group_member) {
        $group_member = $e->retrieve_action_trigger_event_def_group_member($group_member);
        if ($group_member and $U->is_true($group_member->holdings)) {
            $type = 'full';
        }
    }

    $holdings_context_org = $e->retrieve_actor_org_unit($holdings_context_org);

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
        $bucket->owner($e->requestor || 1) 
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

    my $usr_data = {
        type        => $type,
        email       => $email,
        subject     => $subject,
        context_org => $holdings_context_org->shortname,
        sort_by     => $bib_sort,
        sort_dir    => $sort_dir,
        preview     => $preview
    };

    if ($for_print) {

        return $U->fire_object_event(undef, 'biblio.format.record_entry.print', [ $bucket ], $event_context_org, undef, [ $usr_data ]);

    } elsif ($for_email) {

        return $U->fire_object_event(undef, 'biblio.format.record_entry.email', [ $bucket ], $event_context_org, undef, [ $usr_data ])
            if ($preview);

        $U->create_events_for_hook('biblio.format.record_entry.email', $bucket, $event_context_org, undef, $usr_data, 1);
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
            {desc => 'timeout (optional)',  type => 'number'}
        ],
        return => {
            desc => 'Results object like: { "count": $i, "ids": [...] }',
            type => 'object'
        }
    }
);
}

=head3 open-ils.search.biblio.marc (arghash, timeout)

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
# FIXME: sort and limit added.  item_type not tested yet.
# TODO: docache option?
sub marc_search {
    my( $self, $conn, $args, $timeout ) = @_;

    my $method = 'open-ils.storage.biblio.full_rec.multi_search';
    $method .= ".staff" if $self->api_name =~ /staff/;
    $method .= ".atomic";

    my $limit = $args->{limit} || 10;
    my $offset = $args->{offset} || 0;

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
    # a custom call to 'open-ils.storage.biblio.multiclass.search_fts'

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
    return { ids => \@recs, count => int(scalar(@recs)) };
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
    # a custom call to 'open-ils.storage.biblio.multiclass.search_fts'

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
    signature => {
        desc => q/
            For a given record, returns a list of monograph parts with holdable items, their user-readable label, and the number of holdable items with each part.
       /,
       params => [
            {desc => q/Args object:
                rec : bib record id targeted by this hold
                mrec : metarecord id - unused
                pickup_lib : org unit id of pickup library for this hold (for determining if there's a hard boundary)/,
                type => 'object'}
       ],
       return => {
        desc => q/ A list of {id :foo, label : bar, holdable_count : boo} objects for monograph parts with holdable items on the given record. 
            'holdable_count' is the number of holdable items with the part applied to them. /
       }

    }
);

sub rec_hold_parts {
    my( $self, $conn, $args ) = @_;

    my $rec        = $$args{record};
    my $mrec       = $$args{metarecord};
    my $pickup_lib = $$args{pickup_lib};
    my $e = new_editor();

    my $query = {
        from => [
            'asset.count_holdable_parts_on_record',
            $rec,
            $pickup_lib
        ],

    };

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
        from     => {
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
            "+acpl" => { holdable => 't', deleted => 'f' }
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

__PACKAGE__->register_method(
    method   => 'bib_copies',
    api_name => 'open-ils.search.bib.copies',
    stream => 1
);
__PACKAGE__->register_method(
    method   => 'bib_copies',
    api_name => 'open-ils.search.bib.copies.staff',
    stream => 1
);

sub bib_copies {
    my ($self, $client, $rec_id, $org, $depth, $limit, $offset, $pref_ou) = @_;
    my $is_staff = ($self->api_name =~ /staff/);

    my $cstore = OpenSRF::AppSession->create('open-ils.cstore');
    my $req = $cstore->request(
        'open-ils.cstore.json_query', mk_copy_query(
        $rec_id, $org, $depth, $limit, $offset, $pref_ou, $is_staff));

    my $resp;
    while ($resp = $req->recv) {
        my $copy = $resp->content;

        if ($is_staff) {
            # last_circ is an IDL query so it cannot be queried directly
            # via JSON query.
            $copy->{last_circ} = 
                new_editor()->retrieve_reporter_last_circ_date($copy->{id})
                ->last_circ;
        }

        $client->respond($copy);
    }

    return undef;
}

# TODO: this comes almost directly from WWW/EGCatLoader/Record.pm
# Refactor to share
sub mk_copy_query {
    my $rec_id = shift;
    my $org = shift;
    my $depth = shift;
    my $copy_limit = shift;
    my $copy_offset = shift;
    my $pref_ou = shift;
    my $is_staff = shift;
    my $base_query = shift;

    my $query = $base_query || $U->basic_opac_copy_query(
        $rec_id, undef, undef, $copy_limit, $copy_offset, $is_staff
    );

    if ($org) { # TODO: root org test
        # no need to add the org join filter if we're not actually filtering
        $query->{from}->{acp}->[1] = { aou => {
            fkey => 'circ_lib',
            field => 'id',
            filter => {
                id => {
                    in => {
                        select => {aou => [{
                            column => 'id', 
                            transform => 'actor.org_unit_descendants',
                            result_field => 'id', 
                            params => [$depth]
                        }]},
                        from => 'aou',
                        where => {id => $org}
                    }
                }
            }
        }};

        if ($pref_ou) {
            # Make sure the pref OU is included in the results
            my $in = $query->{from}->{acp}->[1]->{aou}->{filter}->{id}->{in};
            delete $query->{from}->{acp}->[1]->{aou}->{filter}->{id};
            $query->{from}->{acp}->[1]->{aou}->{filter}->{'-or'} = [
                {id => {in => $in}},
                {id => $pref_ou}
            ];
        }
    };

    # Unsure if we want these in the shared function, leaving here for now
    unshift(@{$query->{order_by}},
        { class => "aou", field => 'id',
          transform => 'evergreen.rank_ou', params => [$org, $pref_ou]
        }
    );
    push(@{$query->{order_by}},
        { class => "acp", field => 'id',
          transform => 'evergreen.rank_cp'
        }
    );

    return $query;
}

__PACKAGE__->register_method(
    method    => 'record_urls',
    api_name  => 'open-ils.search.biblio.record.resource_urls.retrieve',
    argc      => 1,
    stream    => 1,
    signature => {
        desc   => q/Returns bib record 856 URL content./,
        params => [
            {desc => 'Context org unit ID', type => 'number'},
            {desc => 'Record ID or Array of Record IDs', type => 'number or array'}
        ],
        return => {
            desc => 'Stream of URL objects, one collection object per record',
            type => 'object'
        }
    }
);

sub record_urls {
    my ($self, $client, $org_id, $record_ids) = @_;

    $record_ids = [$record_ids] unless ref $record_ids eq 'ARRAY';

    my $e = new_editor();

    for my $record_id (@$record_ids) {

        my @urls;

        # Start with scoped located URIs
        my $uris = $e->json_query({
            from => ['evergreen.located_uris_as_uris', $record_id, $org_id]});

        for my $uri (@$uris) {
            push(@urls, {
                href => $uri->{href},
                label => $uri->{label},
                note => $uri->{use_restriction}
            });
        }

        # Logic copied from TPAC misc_utils.tts
        my $bib = $e->retrieve_biblio_record_entry($record_id)
            or return $e->event;

        my $marc_doc = $U->marc_xml_to_doc($bib->marc);

        for my $node ($marc_doc->findnodes('//*[@tag="856" and @ind1="4"]')) {

            # asset.uri's
            next if $node->findnodes('./*[@code="9" or @code="w" or @code="n"]');

            my $url = {};
            my ($label) = $node->findnodes('./*[@code="y"]');
            my ($notes) = $node->findnodes('./*[@code="z" or @code="3"]');

            my $first = 1;
            for my $href_node ($node->findnodes('./*[@code="u"]')) {
                next unless $href_node;

                # it's possible for multiple $u's to exist within 1 856 tag.
                # in that case, honor the label/notes data for the first $u, but
                # leave any subsequent $u's as unadorned href's.
                # use href/link/note keys to be consistent with args.uri's

                my $href = $href_node->textContent;
                push(@urls, {
                    href => $href,
                    label => ($first && $label) ?  $label->textContent : $href,
                    note => ($first && $notes) ? $notes->textContent : '',
                    ind2 => $node->getAttribute('ind2')
                });
                $first = 0;
            }
        }

        $client->respond({id => $record_id, urls => \@urls});
    }

    return undef;
}

__PACKAGE__->register_method(
    method    => 'catalog_record_summary',
    api_name  => 'open-ils.search.biblio.record.catalog_summary',
    stream    => 1,
    max_bundle_count => 1,
    signature => {
        desc   => 'Stream of record data suitable for catalog display',
        params => [
            {desc => 'Context org unit ID', type => 'number'},
            {desc => 'Array of Record IDs', type => 'array'},
            {desc => 'Options hash.  Keys can include pref_ou, flesh_copies, copy_limit, copy_depth, copy_offset, and library_group',
                type => 'hashref'}
        ],
        return => { 
            desc => q/
                Stream of record summary objects including id, record,
                hold_count, copy_counts, display (metabib display
                fields), and attributes (metabib record attrs).  The
                metabib variant of the call gets metabib_id and
                metabib_records, and the regular record version also
                gets some metabib information, but returns them as
                staff_view_metabib_id, staff_view_metabib_records, and
                staff_view_metabib_attributes.  This is to mitigate the
                need for code changes elsewhere where assumptions are
                made when certain fields are returned.
                
            /
        }
    }
);
__PACKAGE__->register_method(
    method    => 'catalog_record_summary',
    api_name  => 'open-ils.search.biblio.record.catalog_summary.staff',
    stream    => 1,
    max_bundle_count => 1,
    signature => q/see open-ils.search.biblio.record.catalog_summary/
);
__PACKAGE__->register_method(
    method    => 'catalog_record_summary',
    api_name  => 'open-ils.search.biblio.metabib.catalog_summary',
    stream    => 1,
    max_bundle_count => 1,
    signature => q/see open-ils.search.biblio.record.catalog_summary/
);

__PACKAGE__->register_method(
    method    => 'catalog_record_summary',
    api_name  => 'open-ils.search.biblio.metabib.catalog_summary.staff',
    stream    => 1,
    max_bundle_count => 1,
    signature => q/see open-ils.search.biblio.record.catalog_summary/
);


sub catalog_record_summary {
    my ($self, $client, $org_id, $record_ids, $options) = @_;
    my $e = new_editor();
    $options ||= {};
    my $pref_ou = $options->{pref_ou};
    my $library_group = $options->{library_group};

    my $is_meta = ($self->api_name =~ /metabib/);
    my $is_staff = ($self->api_name =~ /staff/);

    my $holds_method = $is_meta ? 
        'open-ils.circ.mmr.holds.count' : 
        'open-ils.circ.bre.holds.count';

    my $copy_method_name = $is_meta ? 
        'open-ils.search.biblio.metarecord.copy_count':
        'open-ils.search.biblio.record.copy_count';

    $copy_method_name .= '.staff' if $is_staff;

    my $copy_method = $self->method_lookup($copy_method_name); # local method

    my $holdable_method = $is_meta ?
        'open-ils.search.biblio.metarecord.has_holdable_copy':
        'open-ils.search.biblio.record.has_holdable_copy';

    $holdable_method = $self->method_lookup($holdable_method); # local method

    my %MR_summary_cache;
    for my $rec_id (@$record_ids) {

        my $response = $is_meta ? 
            get_one_metarecord_summary($self, $e, $org_id, $rec_id) :
            get_one_record_summary($self, $e, $org_id, $rec_id);

        # Let's get Formats & Editions data FIXME: consider peer bibs?
        my @metabib_records;
        unless ($is_meta) {
            my $meta_search = $e->search_metabib_metarecord_source_map({source => $rec_id});
            if (scalar(@$meta_search) > 0) {
                $response->{staff_view_metabib_id} = $meta_search->[0]->metarecord;
                my $maps = $e->search_metabib_metarecord_source_map({metarecord => $response->{staff_view_metabib_id}});
                @metabib_records = map { $_->source } @$maps;
            } else {
                # XXX ugly hack for bibs without metarecord mappings, e.g. deleted bibs
                # where ingest.metarecord_mapping.preserve_on_delete is false
                @metabib_records = ( $rec_id );
            }

            $response->{staff_view_metabib_records} = \@metabib_records;

            my $metabib_attr = {};
            my $attributes;
            if ($response->{staff_view_metabib_id} and $MR_summary_cache{$response->{staff_view_metabib_id}}) {
                $metabib_attr = $MR_summary_cache{$response->{staff_view_metabib_id}};
            } else {
                $attributes = $U->get_bre_attrs(\@metabib_records);
            }

            # we get "243":{
            #       "srce":{
            #         "code":" ",
            #         "label":"National bibliographic agency"
            #       }, ...}

            if ($attributes) {
                foreach my $bib_id ( keys %{ $attributes } ) {
                    foreach my $ctype ( keys %{ $attributes->{$bib_id} } ) {
                        # we want {
                        #   "srce":{ " ": { "label": "National bibliographic agency", "count" : 1 } },
                        #       ...
                        #   }
                        my $current_code = $attributes->{$bib_id}->{$ctype}->{code};
                        my $code_label = $attributes->{$bib_id}->{$ctype}->{label};
                        $metabib_attr->{$ctype} = {} unless $metabib_attr->{$ctype};
                        if (! $metabib_attr->{$ctype}->{ $current_code }) {
                            $metabib_attr->{$ctype}->{ $current_code } = {
                                "label" => $code_label,
                                "count" => 1
                            }
                        } else {
                            $metabib_attr->{$ctype}->{ $current_code }->{count}++;
                        }
                    }
                }
            }

            if ($response->{staff_view_metabib_id}) {
                $MR_summary_cache{$response->{staff_view_metabib_id}} = $metabib_attr;
            }
            $response->{staff_view_metabib_attributes} = $metabib_attr;
        }

        ($response->{copy_counts}) = $copy_method->run($org_id, $rec_id);

        if ($library_group) {
            my ($group_counts) = $self->method_lookup("$copy_method_name.lasso")->run($org_id, $rec_id, $library_group);
            unshift @{$response->{copy_counts}}, $group_counts->[0];
        }

        $response->{first_call_number} = get_first_call_number(
            $e, $rec_id, $org_id, $is_staff, $is_meta, $options);

        if ($pref_ou) {

            # If we already have the pref ou copy counts, avoid the extra fetch.
            my ($match) = 
                grep {$_->{org_unit} eq $pref_ou} @{$response->{copy_counts}};

            if (!$match) {
                my ($counts) = $copy_method->run($pref_ou, $rec_id);
                ($match) = grep {$_->{org_unit} eq $pref_ou} @$counts;
            }

            $response->{pref_ou_copy_counts} = $match;
        }

        $response->{hold_count} = 
            $U->simplereq('open-ils.circ', $holds_method, $rec_id);

        if ($options->{flesh_copies}) {
            $response->{copies} = get_representative_copies(
                $e, $rec_id, $org_id, $is_staff, $is_meta, $options);
        }

        ($response->{has_holdable_copy}) = $holdable_method->run($rec_id);

        $client->respond($response);
    }

    return undef;
}

# Returns a snapshot of copy information for a given record or metarecord,
# sorted by pref org and search org.
sub get_representative_copies {
    my ($e, $rec_id, $org_id, $is_staff, $is_meta, $options) = @_;

    my @rec_ids;
    my $limit = $options->{copy_limit};
    my $copy_depth = $options->{copy_depth};
    my $copy_offset = $options->{copy_offset};
    my $pref_ou = $options->{pref_ou};

    my $org_tree = $U->get_org_tree;
    if (!$org_id) { $org_id = $org_tree->id; }
    my $org = $U->find_org($org_tree, $org_id);

    return [] unless $org;

    my $func = 'unapi.biblio_record_entry_feed';
    my $includes = '{holdings_xml,acp,acnp,acns,circ}';
    my $limits = "acn=>$limit,acp=>$limit";

    if ($is_meta) {
        $func = 'unapi.metabib_virtual_record_feed';
        $includes = '{holdings_xml,acp,acnp,acns,circ,mmr.unapi}';
        $limits .= ",bre=>$limit";
    }

    my $xml_query = $e->json_query({from => [
        $func, '{'.$rec_id.'}', 'marcxml', 
        $includes, $org->shortname, $copy_depth, $limits,
        undef, undef,undef, undef, undef, 
        undef, undef, undef, $pref_ou
    ]})->[0];

    my $xml = $xml_query->{$func};

    my $doc = XML::LibXML->new->parse_string($xml);

    my $copies = [];
    for my $volume ($doc->documentElement->findnodes('//*[local-name()="volume"]')) {
        my $label = $volume->getAttribute('label');
        my $prefix = $volume->getElementsByTagName('call_number_prefix')->[0]->getAttribute('label');
        my $suffix = $volume->getElementsByTagName('call_number_suffix')->[0]->getAttribute('label');

        my $copies_node = $volume->findnodes('./*[local-name()="copies"]')->[0];

        for my $copy ($copies_node->findnodes('./*[local-name()="copy"]')) {

            my $status = $copy->getElementsByTagName('status')->[0]->textContent;
            my $location = $copy->getElementsByTagName('location')->[0]->textContent;
            my $circ_lib_sn = $copy->getElementsByTagName('circ_lib')->[0]->getAttribute('shortname');
            my $due_date = '';

            my $current_circ = $copy->findnodes('./*[local-name()="current_circulation"]')->[0];
            if (my $circ = $current_circ->findnodes('./*[local-name()="circ"]')) {
                $due_date = $circ->[0]->getAttribute('due_date');
            }

            push(@$copies, {
                call_number_label => $label,
                call_number_prefix_label => $prefix,
                call_number_suffix_label => $suffix,
                circ_lib_sn => $circ_lib_sn,
                copy_status => $status,
                copy_location => $location,
                due_date => $due_date
            });
        }
    }

    return $copies;
}

sub get_first_call_number {
    my ($e, $rec_id, $org_id, $is_staff, $is_meta, $options) = @_;

    my $limit = $options->{copy_limit};
    $options->{copy_limit} = 1;

    my $copies = get_representative_copies(
        $e, $rec_id, $org_id, $is_staff, $is_meta, $options);

    $options->{copy_limit} = $limit;

    return $copies->[0];
}

sub get_one_rec_urls {
    my ($self, $e, $org_id, $bib_id) = @_;

    my ($resp) = $self->method_lookup(
        'open-ils.search.biblio.record.resource_urls.retrieve')
        ->run($org_id, $bib_id);

    return $resp->{urls};
}

# Start with a bib summary and augment the data with additional
# metarecord content.
sub get_one_metarecord_summary {
    my ($self, $e, $org_id, $rec_id) = @_;

    my $meta = $e->retrieve_metabib_metarecord($rec_id) or return {};
    my $maps = $e->search_metabib_metarecord_source_map({metarecord => $rec_id});

    my $bre_id = $meta->master_record; 

    my $response = get_one_record_summary($self, $e, $org_id, $bre_id);
    $response->{urls} = get_one_rec_urls($self, $e, $org_id, $bre_id);

    $response->{metabib_id} = $rec_id;
    $response->{metabib_records} = [map {$_->source} @$maps];

    # Find the sum of record note counts for all mapped bib records
    my @record_ids = map {$_->source} @$maps;
    my $notes = $e->search_biblio_record_note({ record => \@record_ids });
    my $record_note_count = scalar(@{ $notes });
    $response->{record_note_count} = $record_note_count;

    my @other_bibs = map {$_->source} grep {$_->source != $bre_id} @$maps;

    # Augment the record attributes with those of all of the records
    # linked to this metarecord.
    if (@other_bibs) {
        my $attrs = $e->search_metabib_record_attr_flat({id => \@other_bibs});

        my $attributes = $response->{attributes};

        for my $attr (@$attrs) {
            $attributes->{$attr->attr} = [] unless $attributes->{$attr->attr};
            push(@{$attributes->{$attr->attr}}, $attr->value) # avoid dupes
                unless grep {$_ eq $attr->value} @{$attributes->{$attr->attr}};
        }
    }

    return $response;
}

sub get_one_record_summary {
    my ($self, $e, $org_id, $rec_id) = @_;

    my $bre = $e->retrieve_biblio_record_entry([$rec_id, {
        flesh => 1,
        flesh_fields => {
            bre => [qw/compressed_display_entries mattrs creator editor/]
        }
    }]) or return {};

    # Compressed display fields are packaged as JSON
    my $display = {};
    $display->{$_->name} = OpenSRF::Utils::JSON->JSON2perl($_->value)
        foreach @{$bre->compressed_display_entries};

    # Create an object of 'mraf' attributes.
    # Any attribute can be multi so dedupe and array-ify all of them.
    my $attributes = {};
    for my $attr (@{$bre->mattrs}) {
        $attributes->{$attr->attr} = {} unless $attributes->{$attr->attr};
        $attributes->{$attr->attr}->{$attr->value} = 1; # avoid dupes
    }
    $attributes->{$_} = [keys %{$attributes->{$_}}] for keys %$attributes;

    # Find the count of record notes on this record
    my $notes = $e->search_biblio_record_note({ record => $rec_id });
    my $record_note_count = scalar(@{ $notes });

    # clear bulk
    $bre->clear_marc;
    $bre->clear_mattrs;
    $bre->clear_compressed_display_entries;

    return {
        id => $rec_id,
        record => $bre,
        display => $display,
        attributes => $attributes,
        urls => get_one_rec_urls($self, $e, $org_id, $rec_id),
        record_note_count => $record_note_count
    };
}

__PACKAGE__->register_method(
    method    => 'record_copy_counts_global',
    api_name  => 'open-ils.search.biblio.record.copy_counts.global.staff',
    signature => {
        desc   => q/Returns a count of copies and call numbers for each org
                    unit, including items attached to each org unit plus
                    a sum of counts for all descendants./,
        params => [
            {desc => 'Record ID', type => 'number'}
        ],
        return => {
            desc => 'Hash of org unit ID  => {copy: $count, call_number: $id}'
        }
    }
);

sub record_copy_counts_global {
    my ($self, $client, $rec_id) = @_;

    my $copies = new_editor()->json_query({
        select => {
            acp => [{column => 'id', alias => 'copy_id'}, 'circ_lib'],
            acn => [{column => 'id', alias => 'cn_id'}, 'owning_lib']
        },
        from => {acn => {acp => {type => 'left'}}},
        where => {
            '+acp' => {
                '-or' => [
                    {deleted => 'f'},
                    {id => undef} # left join
                ]
            },
            '+acn' => {deleted => 'f', record => $rec_id}
        }
    });

    my $hash = {};
    my %seen_cn;

    for my $copy (@$copies) {
        my $org = $copy->{circ_lib} || $copy->{owning_lib};
        $hash->{$org} = {copies => 0, call_numbers => 0} unless $hash->{$org};
        $hash->{$org}->{copies}++ if $copy->{circ_lib};

        if (!$seen_cn{$copy->{cn_id}}) {
            $seen_cn{$copy->{cn_id}} = 1;
            $hash->{$org}->{call_numbers}++;
        }
    }

    my $sum;
    $sum = sub {
        my $node = shift;
        my $h = $hash->{$node->id} || {copies => 0, call_numbers => 0};
        delete $h->{cn_id};

        for my $child (@{$node->children}) {
            my $vals = $sum->($child);
            $h->{copies} += $vals->{copies};
            $h->{call_numbers} += $vals->{call_numbers};
        }

        $hash->{$node->id} = $h;

        return $h;
    };

    $sum->($U->get_org_tree);

    return $hash;
}

__PACKAGE__->register_method(
    method        => "fetch_in_scope_lassos",
    api_name      => "open-ils.search.fetch_context_library_groups",
    stream        => 1,
    signature     => {
        desc   => "Fetch global and in-scope library groups (lassos)",
        params => [
            { desc => 'Optional org unit id for context scoping' }
        ],
        return => {
            desc => 'Stream (or array, in atomic mode) of library groups (lassos)'
        }
    }
);

__PACKAGE__->register_method(
    method        => "fetch_in_scope_lassos",
    api_name      => "open-ils.search.fetch_context_library_groups.opac",
    stream        => 1,
    signature     => {
        desc   => "Fetch global and in-scope library groups (lassos) for the OPAC",
        params => [
            { desc => 'Optional org unit id for context scoping' }
        ],
        return => {
            desc => 'Stream (or array, in atomic mode) of library groups (lassos)'
        }
    }
);

sub fetch_in_scope_lassos {
    my( $self, $client, $org ) = @_;
    my $e = new_editor();

    my $direct_lassos = [];

    # this supports a scalar org id, or an array of them
    if ($org and (!ref($org) or ref($org) eq 'ARRAY')) {
        $direct_lassos = $e->search_actor_org_lasso_map(
            { org_unit => $org }
        );
        $direct_lassos = [ map { $_->lasso } @$direct_lassos];
    }

    my $lassos = $e->search_actor_org_lasso({
        $self->api_name =~ /opac/ ? (opac_visible => 't') : (),
            '-or' => {
            global => 't',
            @$direct_lassos ? (id => { in => $direct_lassos}) : ()
            }
    });

    $client->respond($_) for sort { $a->name cmp $b->name } @$lassos;
    return undef;
}

1;

