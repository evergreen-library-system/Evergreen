package OpenILS::Application::Storage::Publisher::container;
use base qw/OpenILS::Application::Storage/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw/:level :logger/;
use OpenILS::Utils::CStoreEditor;
#use OpenILS::Application::Storage::CDBI::config;

my $new_items_query = q(
    WITH c_attr AS (SELECT c_attrs::query_int AS vis_test FROM asset.patron_default_visibility_mask() x)
    SELECT acn.record AS bib
    FROM asset.call_number acn
    JOIN asset.copy acp ON (acp.call_number = acn.id)
    JOIN asset.copy_location acpl ON (acp.location = acpl.id)
    JOIN config.copy_status ccs ON (acp.status = ccs.id)
    , c_attr
    WHERE acn.owning_lib IN (ORG_LIST)
    AND acp.circ_lib IN (ORG_LIST)
    AND acp.holdable
    AND acp.circulate
    AND acp.deleted is false
    AND ccs.holdable
    AND acpl.holdable
    AND acpl.circulate
    AND acp.active_date > NOW() - ?::INTERVAL
    -- LOC AND acp.location IN (LOC_LIST)
    AND (EXISTS (SELECT 1 FROM asset.copy_vis_attr_cache WHERE record = acn.record AND vis_attr_vector @@ c_attr.vis_test))
    AND (NOT EXISTS (SELECT 1 FROM metabib.record_attr_vector_list WHERE source = acn.record AND vlist @@ metabib.compile_composite_attr(' {"1":[{"_val":"s","_attr":"bib_level"}]}')::query_int))
    GROUP BY acn.record
    ORDER BY MIN(AGE(acp.active_date))
    LIMIT ? 
);
my $recently_returned_query = q(
WITH c_attr AS (SELECT c_attrs::query_int AS vis_test FROM asset.patron_default_visibility_mask() x)
    SELECT acn.record AS bib
    FROM asset.call_number acn
    JOIN asset.copy acp ON (acp.call_number = acn.id)
    JOIN asset.copy_location acpl ON (acp.location = acpl.id)
    JOIN config.copy_status ccs ON (acp.status = ccs.id)
    JOIN action.circulation circ ON (circ.target_copy = acp.id)
    , c_attr
    WHERE acn.owning_lib IN (ORG_LIST)
    AND acp.circ_lib IN (ORG_LIST)
    AND acp.holdable
    AND acp.circulate
    AND acp.deleted is false
    AND ccs.holdable
    AND acpl.holdable
    AND acpl.circulate
    AND circ.checkin_time > NOW() - ?::INTERVAL
    AND circ.checkin_time IS NOT NULL
    -- LOC AND acp.location IN (LOC_LIST)
    AND (EXISTS (SELECT 1 FROM asset.copy_vis_attr_cache WHERE record = acn.record AND vis_attr_vector @@ c_attr.vis_test))
    AND (NOT EXISTS (SELECT 1 FROM metabib.record_attr_vector_list WHERE source = acn.record AND vlist @@ metabib.compile_composite_attr(' {"1":[{"_val":"s","_attr":"bib_level"}]}')::query_int))
    GROUP BY acn.record
    ORDER BY MIN(AGE(circ.checkin_time))
    LIMIT ?
);
my $top_circs_query = q(
    WITH c_attr AS (SELECT c_attrs::query_int AS vis_test FROM asset.patron_default_visibility_mask() x)
    SELECT acn.record AS bib
    FROM asset.call_number acn
    JOIN asset.copy acp ON (acp.call_number = acn.id)
    JOIN asset.copy_location acpl ON (acp.location = acpl.id)
    JOIN config.copy_status ccs ON (acp.status = ccs.id)
    JOIN action.circulation circ ON (circ.target_copy = acp.id)
    , c_attr
    WHERE acn.owning_lib IN (ORG_LIST)
    AND acp.circ_lib IN (ORG_LIST)
    AND acp.holdable
    AND acp.circulate
    AND acp.deleted is false
    AND ccs.holdable
    AND acpl.holdable
    AND acpl.circulate
    AND circ.xact_start > NOW() - ?::INTERVAL
    -- LOC AND acp.location IN (LOC_LIST)
    AND (EXISTS (SELECT 1 FROM asset.copy_vis_attr_cache WHERE record = acn.record AND vis_attr_vector @@ c_attr.vis_test))
    AND (NOT EXISTS (SELECT 1 FROM metabib.record_attr_vector_list WHERE source = acn.record AND vlist @@ metabib.compile_composite_attr(' {"1":[{"_val":"s","_attr":"bib_level"}]}')::query_int))
    GROUP BY acn.record
    ORDER BY COUNT(circ.id) DESC
    LIMIT ?
);
my $new_by_loc_query = q(
    WITH c_attr AS (SELECT c_attrs::query_int AS vis_test FROM asset.patron_default_visibility_mask() x)
    SELECT acn.record AS bib
    FROM asset.call_number acn
    JOIN asset.copy acp ON (acp.call_number = acn.id)
    JOIN asset.copy_location acpl ON (acp.location = acpl.id)
    JOIN config.copy_status ccs ON (acp.status = ccs.id)
    , c_attr
    WHERE acn.owning_lib IN (ORG_LIST)
    AND acp.circ_lib IN (ORG_LIST)
    AND acp.active_date > NOW() - ?::INTERVAL
    -- LOC AND acp.location IN (LOC_LIST)
    AND acp.holdable
    AND acp.circulate
    AND acp.deleted is false
    AND ccs.holdable
    AND acpl.holdable
    AND acpl.circulate
    AND (EXISTS (SELECT 1 FROM asset.copy_vis_attr_cache WHERE record = acn.record AND vis_attr_vector @@ c_attr.vis_test))
    AND (NOT EXISTS (SELECT 1 FROM metabib.record_attr_vector_list WHERE source = acn.record AND vlist @@ metabib.compile_composite_attr(' {"1":[{"_val":"s","_attr":"bib_level"}]}')::query_int))
    GROUP BY acn.record
    ORDER BY MIN(AGE(acp.active_date))
    LIMIT ?
);

my %TYPE_QUERY_MAP = (
    2 => $new_items_query,
    3 => $recently_returned_query,
    4 => $top_circs_query,
    5 => $new_by_loc_query,
);

sub refresh_container_from_carousel_definition {
    my $self = shift;
    my $client = shift;
    my $bucket = shift;
    my $carousel_type = shift;
    my $age = shift // '15 days';
    my $libs = shift // [];
    my $locs = shift // [];
    my $limit = shift // 50;

    my $e = OpenILS::Utils::CStoreEditor->new;
    my $ctype = $e->retrieve_config_carousel_type($carousel_type) or return $e->die_event;
    $e->disconnect;

    unless (exists($TYPE_QUERY_MAP{$carousel_type})) {
        $logger->error("Carousel for bucket $bucket is misconfigured; type $carousel_type is not recognized");
        return 0;
    }

    my $query = $TYPE_QUERY_MAP{$carousel_type};

    if ($ctype->filter_by_copy_owning_lib eq 't') {
        if (scalar(@$libs) < 1) {
            $logger->error("Carousel for bucket $bucket is misconfigured; owning library filter expected but none specified");
            return 0;
        }
        my $org_placeholders = join(',', map { '?' } @$libs);
        $query =~ s/ORG_LIST/$org_placeholders/g;
    } else {
        $libs = []; # we'll ignore any superflous supplied values
    }

    if ($ctype->filter_by_copy_location eq 't') {
        if (scalar(@$locs) < 1) {
            $logger->error("Carousel for bucket $bucket is misconfigured; copy location filter expected but none specified");
            return 0;
        }
        my $loc_placeholders = join(',', map { '?' } @$locs);
        $query =~ s/-- LOC //g;
        $query =~ s/LOC_LIST/$loc_placeholders/g;
    } else {
        $locs = []; # we'll ignore any superflous supplied values
    }

    my $sth = container::biblio_record_entry_bucket_item->db_Main->prepare_cached($query);

    $sth->execute(@$libs, @$libs, $age, @$locs, $limit);
    my @bibs = ();
    while (my $row = $sth->fetchrow_hashref ) {
        push @bibs, $row->{bib};
    }
    container::biblio_record_entry_bucket_item->search( bucket => $bucket )->delete_all;
    my $i = 0;
    foreach my $bib (@bibs) {
        container::biblio_record_entry_bucket_item->create({ bucket => $bucket, target_biblio_record_entry => $bib, pos => $i++ });
    }
    return scalar(@bibs);
}

__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.container.refresh_from_carousel',
    method      => 'refresh_container_from_carousel_definition',
    api_level   => 1,
    cachable    => 1,
);

sub refresh_all_carousels {
    my $self = shift;
    my $client = shift;

    my $e = OpenILS::Utils::CStoreEditor->new;

    my $automatic_types = $e->search_config_carousel_type({ automatic => 't' });
    my $carousels = $e->search_container_carousel({ type => [ map { $_->id } @$automatic_types ], active => 't' });

    my $meth = $self->method_lookup('open-ils.storage.container.refresh_from_carousel');

    foreach my $carousel (@$carousels) {

        my $orgs = [];
        my $locs = [];
        if (defined($carousel->owning_lib_filter)) {
            my $ou_filter = $carousel->owning_lib_filter;
            $ou_filter =~ s/[{}]//g;
            @$orgs = split /,/, $ou_filter;
        }
        if (defined($carousel->copy_location_filter)) {
            my $loc_filter = $carousel->copy_location_filter;
            $loc_filter =~ s/[{}]//g;
            @$locs = split /,/, $loc_filter;
        }

        my @res = $meth->run($carousel->bucket, $carousel->type, $carousel->age_filter, $orgs, $locs, $carousel->max_items);
        my $ct = scalar(@res) ? $res[0] : 0;

        $e->xact_begin;
        $carousel->last_refresh_time('now');
        $e->update_container_carousel($carousel);
        $e->xact_commit;

        $client->respond({
            carousel => $carousel->id,
            bucket   => $carousel->bucket,
            updated  => $ct
        });

    }
    $e->disconnect;
    return undef;
}

__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.carousel.refresh_all',
    method      => 'refresh_all_carousels',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);


1;
