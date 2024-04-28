package OpenILS::Application::Storage::Publisher::biblio;
use base qw/OpenILS::Application::Storage/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Utils::Fieldmapper;

$VERSION = 1;

sub record_copy_count {
    my $self = shift;
    my $client = shift;

    my %args = @_;

    my $cn_table = asset::call_number->table;
    my $cp_table = asset::copy->table;
    my $st_table = config::copy_status->table;
    my $src_table = config::bib_source->table;
    my $br_table = biblio::record_entry->table;
    my $loc_table = asset::copy_location->table;
    my $out_table = actor::org_unit_type->table;

    my $descendants = "actor.org_unit_descendants(u.id)";
    my $ancestors = "actor.org_unit_ancestors(?) u JOIN $out_table t ON (u.ou_type = t.id)";

    if ($args{org_unit} < 0) {
        $args{org_unit} *= -1;
        $ancestors = "(select org_unit as id from actor.org_lasso_map where lasso = ?) u CROSS JOIN (SELECT -1 AS depth) t";
    }

    my $visible = 'AND a.opac_visible = TRUE AND st.opac_visible = TRUE AND loc.opac_visible = TRUE AND cp.opac_visible = TRUE';
    if ($self->api_name =~ /staff/o) {
        $visible = ''
    }

    my $sql = <<"    SQL";
        SELECT  t.depth,
            u.id AS org_unit,
            sum(
                (SELECT count(cp.id)
                  FROM  $cn_table cn
                    JOIN $cp_table cp ON (cn.id = cp.call_number)
                    JOIN $descendants a ON (cp.circ_lib = a.id)
                    JOIN $st_table st ON (cp.status = st.id)
                    JOIN $loc_table loc ON (cp.location = loc.id)
                  WHERE cn.record = ?
                    $visible
                    AND cn.deleted IS FALSE
                    AND cp.deleted IS FALSE
                    AND loc.deleted IS FALSE)
            ) AS count,
            sum(
                (SELECT count(cp.id)
                  FROM  $cn_table cn
                    JOIN $cp_table cp ON (cn.id = cp.call_number)
                    JOIN $descendants a ON (cp.circ_lib = a.id)
                    JOIN $st_table st ON (cp.status = st.id)
                    JOIN $loc_table loc ON (cp.location = loc.id)
                  WHERE cn.record = ?
                    $visible
                    AND cn.deleted IS FALSE
                    AND cp.deleted IS FALSE
                    AND loc.deleted IS FALSE
                    AND cp.status IN (0,7,12))
            ) AS available,
            sum(
                (SELECT count(cp.id)
                  FROM  $cn_table cn
                    JOIN $cp_table cp ON (cn.id = cp.call_number)
                    JOIN $st_table st ON (cp.status = st.id)
                    JOIN $loc_table loc ON (cp.location = loc.id)
                  WHERE cn.record = ?
                    AND st.opac_visible = TRUE
                    AND loc.opac_visible = TRUE
                    AND cp.opac_visible = TRUE
                    AND cn.deleted IS FALSE
                    AND cp.deleted IS FALSE
                    AND loc.deleted IS FALSE)
            ) AS unshadow,
                        sum(    
                                (SELECT sum(1)
                                  FROM  $br_table br
                                        JOIN $src_table src ON (src.id = br.source)
                                  WHERE br.id = ?
                                        AND src.transcendant IS TRUE
                                )
                        ) AS transcendant
          FROM  $ancestors
          GROUP BY 1,2
    SQL

    my $sth = biblio::record_entry->db_Main->prepare_cached($sql);
    $sth->execute(''.$args{record}, ''.$args{record}, ''.$args{record}, ''.$args{record}, ''.$args{org_unit});
    while ( my $row = $sth->fetchrow_hashref ) {
        $client->respond( $row );
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.record_entry.copy_count',
    method      => 'record_copy_count',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.record_entry.copy_count.staff',
    method      => 'record_copy_count',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);

sub record_ranged_tree {
    my $self = shift;
    my $client = shift;
    my $r = shift;
    my $ou = shift;
    my $depth = shift;
    my $limit = shift || 0;
    my $offset = shift || 0;

    my $ou_sql = defined($depth) ?
            "SELECT id FROM actor.org_unit_descendants(?,?)":
            "SELECT id FROM actor.org_unit_descendants(?)";

    my $ou_list =
        actor::org_unit
            ->db_Main
            ->selectcol_arrayref(
                $ou_sql,
                {},
                $ou,
                (defined($depth) ? ($depth) : ()),
            );

    return undef unless ($ou_list and @$ou_list);

    $r = biblio::record_entry->retrieve( $r );
    return undef unless ($r);

    my $rec = $r->to_fieldmapper;
    $rec->call_numbers([]);

    $rec->fixed_fields( $r->record_descriptor->next->to_fieldmapper );

    my $offset_count = 0;
    my $limit_count = 0;
    for my $cn ( $r->call_numbers  ) {
        next if ($cn->deleted);
        my $call_number = $cn->to_fieldmapper;
        $call_number->copies([]);


        for my $cp ( $cn->copies(circ_lib => $ou_list) ) {
            next if ($cp->deleted);
            if ($offset > 0 && $offset_count < $offset) {
                $offset_count++;
                next;
            }
            
            last if ($limit > 0 && $limit_count >= $limit);

            my $copy = $cp->to_fieldmapper;
            $copy->status( $cp->status->to_fieldmapper );
            $copy->location( $cp->location->to_fieldmapper );
            push @{ $call_number->copies }, $copy;

            $limit_count++;
        }

        last if ($limit > 0 && $limit_count >= $limit);

        push @{ $rec->call_numbers }, $call_number if (@{ $call_number->copies });
    }

    return $rec;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.record_entry.ranged_tree',
    method      => 'record_ranged_tree',
    argc        => 1,
    api_level   => 1,
);


sub regenerate_badge_list {
    my $self = shift;
    my $client = shift;

    my $sth = biblio::record_entry->db_Main->prepare_cached( <<"    SQL" );
        SELECT  r.id AS badge
          FROM  rating.badge r
          WHERE r.last_calc < NOW() - r.recalc_interval
                OR r.last_calc IS NULL
          ORDER BY r.last_calc ASC NULLS FIRST -- oldest first
    SQL

    $sth->execute;
    while ( my $row = $sth->fetchrow_hashref ) {
        $client->respond( $row->{badge} );
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.regenerate_badge_list',
    method      => 'regenerate_badge_list',
    api_level   => 1,
    cachable    => 1,
);


sub record_by_barcode {
    my $self = shift;
    my $client = shift;

    my $cn_table = asset::call_number->table;
    my $cp_table = asset::copy->table;

    my $id = ''.shift;
    my ($r) = biblio::record_entry->db_Main->selectrow_array( <<"    SQL", {}, $id );
        SELECT  cn.record
          FROM  $cn_table cn
            JOIN $cp_table cp ON (cp.call_number = cn.id)
          WHERE cp.barcode = ?
    SQL

    my $rec = biblio::record_entry->retrieve( $r );

    return $rec->to_fieldmapper if ($rec);
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.record_entry.retrieve_by_barcode',
    method      => 'record_by_barcode',
    api_level   => 1,
    cachable    => 1,
);

sub record_by_copy {
    my $self = shift;
    my $client = shift;

    my $cn_table = asset::call_number->table;
    my $cp_table = asset::copy->table;

    my $id = ''.shift;
    my ($r) = biblio::record_entry->db_Main->selectrow_array( <<"    SQL", {}, $id );
        SELECT  cn.record
          FROM  $cn_table cn
            JOIN $cp_table cp ON (cp.call_number = cn.id)
          WHERE cp.id = ?
    SQL

    my $rec = biblio::record_entry->retrieve( $r );
    return undef unless ($rec);

    my $r_fm = $rec->to_fieldmapper;
    my $ff = $rec->record_descriptor->next;
    $r_fm->fixed_fields( $ff->to_fieldmapper ) if ($ff);

    return $r_fm;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy',
    method      => 'record_by_copy',
    api_level   => 1,
    cachable    => 1,
);

sub global_record_copy_count {
    my $self = shift;
    my $client = shift;

    my $rec = shift;

    my $cn_table = asset::call_number->table;
    my $cp_table = asset::copy->table;
    my $cl_table = asset::copy_location->table;
    my $cs_table = config::copy_status->table;

    my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';
    $copies_visible = '' if ($self->api_name =~ /staff/o);

    my $sql = <<"    SQL";

        SELECT  owning_lib, sum(avail), sum(tot)
          FROM  (
                    SELECT  cn.owning_lib, count(cp.id) as avail, 0 as tot
                  FROM  $cn_table cn
                    JOIN $cp_table cp ON (cn.id = cp.call_number)
                    JOIN $cs_table cs ON (cs.id = cp.status)
                    JOIN $cl_table cl ON (cl.id = cp.location)
                  WHERE cn.record = ?
                    AND cp.status IN (0,7,12)
                    $copies_visible
                  GROUP BY 1
                                    UNION
                    SELECT  cn.owning_lib, 0 as avail, count(cp.id) as tot
                  FROM  $cn_table cn
                    JOIN $cp_table cp ON (cn.id = cp.call_number)
                    JOIN $cs_table cs ON (cs.id = cp.status)
                    JOIN $cl_table cl ON (cl.id = cp.location)
                  WHERE cn.record = ?
                    $copies_visible
                  GROUP BY 1
            ) x
          GROUP BY 1
    SQL

    my $sth = biblio::record_entry->db_Main->prepare_cached($sql);
    $sth->execute("$rec", "$rec");

    $client->respond( $_ ) for (@{$sth->fetchall_arrayref});
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.record_entry.global_copy_count',
    method      => 'global_record_copy_count',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.record_entry.global_copy_count.staff',
    method      => 'global_record_copy_count',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);

sub record_copy_status_count {
    my $self = shift;
    my $client = shift;

    my $rec = shift;
    my $ou = shift || 1;
    my $depth = shift || 0;


    my $descendants = "actor.org_unit_descendants(?,?)";

    my $cn_table = asset::call_number->table;
    my $cnp_table = asset::call_number_prefix->table;
    my $cns_table = asset::call_number_suffix->table;
    my $cp_table = asset::copy->table;
    my $cl_table = asset::copy_location->table;
    my $cs_table = config::copy_status->table;

    my $sql = <<"    SQL";

        SELECT  cp.circ_lib,
                CASE WHEN cnp.id > -1 THEN cnp.label ELSE '' END,
                cn.label,
                CASE WHEN cns.id > -1 THEN cns.label ELSE '' END,
                cp.status,
                count(cp.id)
          FROM  $cp_table cp,
            $cn_table cn,
            $cns_table cns,
            $cnp_table cnp,
            $cl_table cl,
            $cs_table cs,
            $descendants d
          WHERE cn.record = ?
            AND cnp.id = cn.prefix
            AND cns.id = cn.suffix
            AND cp.call_number = cn.id
            AND cp.location = cl.id
            AND cp.circ_lib = d.id
            AND cp.status = cs.id
            AND cl.opac_visible IS TRUE
            AND cp.opac_visible IS TRUE
            AND cp.deleted IS FALSE
            AND cl.deleted IS FALSE
            AND cs.opac_visible IS TRUE
          GROUP BY 1,2,3,4,5;
    SQL

    my $sth = biblio::record_entry->db_Main->prepare_cached($sql);
    $sth->execute($ou, $depth, "$rec" );

    my %data = ();
    for my $row (@{$sth->fetchall_arrayref}) {
        $data{$$row[0]}{$$row[1]}{$$row[2]}{$$row[3]}{$$row[4]} += $$row[5];
    }
    
    for my $ou (keys %data) {
        for my $cn_prefix (keys %{$data{$ou}}) {
            for my $cn (keys %{$data{$ou}{$cn_prefix}}) {
                for my $cn_suffix (keys %{$data{$ou}{$cn_prefix}{$cn}}) {
                    $client->respond( [$ou, $cn_prefix, $cn, $cn_suffix, $data{$ou}{$cn}{$cn_prefix}{$cn}{$cn_suffix}] );
                }
            }
        }
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.record_entry.status_copy_count',
    method      => 'record_copy_status_count',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);


sub record_copy_status_location_count {
    my $self = shift;
    my $client = shift;

    my $rec = shift;
    my $ou = shift || 1;
    my $depth = shift || 0;


    my $descendants = "actor.org_unit_descendants(?,?)";

    my $cn_table = asset::call_number->table;
    my $cnp_table = asset::call_number_prefix->table;
    my $cns_table = asset::call_number_suffix->table;
    my $cp_table = asset::copy->table;
    my $cl_table = asset::copy_location->table;
    my $cs_table = config::copy_status->table;

    # FIXME using oils_i18n_xlate here is exposing a hitherto unexposed
    # implementation detail of json_query; doing it this way because
    # json_query currently doesn't grok joining a function to tables
    my $sql = <<"    SQL";

        SELECT  cp.circ_lib,
                CASE WHEN cnp.id > -1 THEN cnp.label ELSE '' END,
                cn.label,
                CASE WHEN cns.id > -1 THEN cns.label ELSE '' END,
                oils_i18n_xlate('asset.copy_location', 'acpl', 'name', 'id', cl.id::TEXT, ?),
                cp.status,
                count(cp.id)
          FROM  $cp_table cp,
            $cn_table cn,
            $cns_table cns,
            $cnp_table cnp,
            $cl_table cl,
            $cs_table cs,
            $descendants d
          WHERE cn.record = ?
            AND cnp.id = cn.prefix
            AND cns.id = cn.suffix
            AND cp.call_number = cn.id
            AND cp.location = cl.id
            AND cp.circ_lib = d.id
            AND cp.status = cs.id
            AND cl.opac_visible IS TRUE
            AND cp.opac_visible IS TRUE
            AND cp.deleted IS FALSE
            AND cl.deleted IS FALSE
            AND cs.opac_visible IS TRUE
          GROUP BY 1,2,3,4,5,6;
    SQL

    my $sth = biblio::record_entry->db_Main->prepare_cached($sql);
    my $ses_locale = $client->session ? $client->session->session_locale : 'en-US';
    $sth->execute($ses_locale, $ou, $depth, "$rec" );

    my %data = ();
    for my $row (@{$sth->fetchall_arrayref}) {
        $data{$$row[0]}{$$row[1]}{$$row[2]}{$$row[3]}{$$row[4]}{$$row[5]} += $$row[6];
    }
    
    for my $ou (keys %data) {
        for my $cn_prefix (keys %{$data{$ou}}) {
            for my $cn (keys %{$data{$ou}{$cn_prefix}}) {
                for my $cn_suffix (keys %{$data{$ou}{$cn_prefix}{$cn}}) {
                    for my $cl (keys %{$data{$ou}{$cn_prefix}{$cn}{$cn_suffix}}) {
                        $client->respond( [$ou, $cn_prefix, $cn, $cn_suffix, $cl, $data{$ou}{$cn_prefix}{$cn}{$cn_suffix}{$cl}] );
                    }
                }
            }
        }
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.record_entry.status_copy_location_count',
    method      => 'record_copy_status_location_count',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);

1;
