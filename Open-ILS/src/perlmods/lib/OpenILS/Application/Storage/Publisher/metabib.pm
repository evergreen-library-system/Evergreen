package OpenILS::Application::Storage::Publisher::metabib;
use base qw/OpenILS::Application::Storage::Publisher/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::FTS;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/:level/;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::JSON;
use List::MoreUtils qw(uniq);
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;

use OpenILS::Application::Storage::QueryParser;

my $U = 'OpenILS::Application::AppUtils';

my $log = 'OpenSRF::Utils::Logger';

$VERSION = 1;

sub _initialize_parser {
    my ($parser) = @_;

    my $cstore = OpenSRF::AppSession->create( 'open-ils.cstore' );
    $parser->initialize(
        config_record_attr_index_norm_map =>
            $cstore->request(
                'open-ils.cstore.direct.config.record_attr_index_norm_map.search.atomic',
                { id => { "!=" => undef } },
                { flesh => 1, flesh_fields => { crainm => [qw/norm/] }, order_by => [{ class => "crainm", field => "pos" }] }
            )->gather(1),
        search_relevance_adjustment         =>
            $cstore->request(
                'open-ils.cstore.direct.search.relevance_adjustment.search.atomic',
                { id => { "!=" => undef } }
            )->gather(1),
        config_metabib_field                =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_field.search.atomic',
                { id => { "!=" => undef } }
            )->gather(1),
        config_metabib_field_virtual_map    =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_field_virtual_map.search.atomic',
                { id => { "!=" => undef } }
            )->gather(1),
        config_metabib_search_alias         =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_search_alias.search.atomic',
                { alias => { "!=" => undef } }
            )->gather(1),
        config_metabib_field_index_norm_map =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_field_index_norm_map.search.atomic',
                { id => { "!=" => undef } },
                { flesh => 1, flesh_fields => { cmfinm => [qw/norm/] }, order_by => [{ class => "cmfinm", field => "pos" }] }
            )->gather(1),
        config_record_attr_definition       =>
            $cstore->request(
                'open-ils.cstore.direct.config.record_attr_definition.search.atomic',
                { name => { "!=" => undef } }
            )->gather(1),
        config_metabib_class_ts_map         =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_class_ts_map.search.atomic',
                { active => "t" }
            )->gather(1),
        config_metabib_field_ts_map         =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_field_ts_map.search.atomic',
                { active => "t" }
            )->gather(1),
        config_metabib_class                =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_class.search.atomic',
                { name => { "!=" => undef } }
            )->gather(1),
    );

    my $max_mult;
    my $cgf = $cstore->request(
        'open-ils.cstore.direct.config.global_flag.retrieve',
        'search.max_popularity_importance_multiplier'
    )->gather(1);
    $max_mult = $cgf->value if $cgf && $U->is_true($cgf->enabled);
    $max_mult //= 2.0;
    $max_mult = 2.0 unless $max_mult =~ /^-?(?:\d+\.?|\.\d)\d*\z/; # just in case
    $parser->max_popularity_importance_multiplier($max_mult);
    $parser->dbh(biblio::record_entry->db_Main);

    $cstore->disconnect;
    die("Cannot initialize $parser!") unless ($parser->initialization_complete);
}

sub ordered_records_from_metarecord { # XXX Replace with QP-based search-within-MR
    my $self = shift;
    my $client = shift;
    my $mr = shift;
    my $formats = shift; # dead
    my $org = shift;
    my $depth = shift;

    my $copies_visible = 'LEFT JOIN asset.copy_vis_attr_cache vc ON (br.id = vc.record '.
                         'AND vc.vis_attr_vector @@ (SELECT c_attrs::query_int FROM asset.patron_default_visibility_mask() LIMIT 1))';
    $copies_visible = '' if ($self->api_name =~ /staff/o);

    my $copies_visible_count = ',COUNT(vc.id)';
    $copies_visible_count = '' if ($self->api_name =~ /staff/o);

    my $descendants = '';
    if ($org) {
        $descendants = defined($depth) ?
            ",actor.org_unit_descendants($org, $depth) d" :
            ",actor.org_unit_descendants($org) d" ;
    }

    my $sql = <<"    SQL";
        SELECT  br.id,
                br.quality,
                s.value
                $copies_visible_count
          FROM  metabib.metarecord_source_map sm
                JOIN biblio.record_entry br ON (sm.source = br.id AND NOT br.deleted)
                LEFT JOIN metabib.record_sorter s ON (s.source = br.id AND s.attr = 'titlesort')
                LEFT JOIN config.bib_source bs ON (br.source = bs.id)
                $copies_visible
                $descendants
          WHERE sm.metarecord = ?
    SQL

    my $having = '';
    if ($copies_visible) {
        $sql .= 'AND (bs.transcendant OR ';
        if ($descendants) {
                $sql .= 'vc.circ_lib = d.id)';
        } else {
            $sql .= 'vc.id IS NOT NULL)'
        }
        $having = 'HAVING COUNT(vc.id) > 0';
    }

    $sql .= <<"    SQL";
      GROUP BY 1, 2, 3
      $having
      ORDER BY
        br.quality DESC,
        s.value ASC NULLS LAST
    SQL

    my $ids = metabib::metarecord_source_map->db_Main->selectcol_arrayref($sql, {}, "$mr");
    return $ids if ($self->api_name =~ /atomic$/o);

    $client->respond( $_ ) for ( @$ids );
    return undef;

}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.ordered.metabib.metarecord.records',
    no_tz_force => 1,
    method      => 'ordered_records_from_metarecord',
    api_level   => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.ordered.metabib.metarecord.records.staff',
    no_tz_force => 1,
    method      => 'ordered_records_from_metarecord',
    api_level   => 1,
    cachable    => 1,
);

__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.ordered.metabib.metarecord.records.atomic',
    no_tz_force => 1,
    method      => 'ordered_records_from_metarecord',
    api_level   => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.ordered.metabib.metarecord.records.staff.atomic',
    no_tz_force => 1,
    method      => 'ordered_records_from_metarecord',
    api_level   => 1,
    cachable    => 1,
);

sub metarecord_copy_count {
    my $self = shift;
    my $client = shift;

    my %args = @_;

    my $sm_table = metabib::metarecord_source_map->table;
    my $rd_table = metabib::record_descriptor->table;
    my $cn_table = asset::call_number->table;
    my $cp_table = asset::copy->table;
    my $br_table = biblio::record_entry->table;
    my $src_table = config::bib_source->table;
    my $cl_table = asset::copy_location->table;
    my $cs_table = config::copy_status->table;
    my $out_table = actor::org_unit_type->table;

    my $descendants = "actor.org_unit_descendants(u.id)";
    my $ancestors = "actor.org_unit_ancestors(?) u JOIN $out_table t ON (u.ou_type = t.id)";

    if ($args{org_unit} < 0) {
        $args{org_unit} *= -1;
        $ancestors = "(select org_unit as id from actor.org_lasso_map where lasso = ?) u CROSS JOIN (SELECT -1 AS depth) t";
    }

    my $copies_visible = 'AND a.opac_visible IS TRUE AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';
    $copies_visible = '' if ($self->api_name =~ /staff/o);

    my (@types,@forms,@blvl);
    my ($t_filter, $f_filter, $b_filter) = ('','','');

    if ($args{format}) {
        my ($t, $f, $b) = split '-', $args{format};
        @types = split '', $t;
        @forms = split '', $f;
        @blvl = split '', $b;

        if (@types) {
            $t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
        }

        if (@forms) {
            $f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
        }

        if (@blvl) {
            $b_filter .= ' AND rd.bib_level IN ('.join(',',map{'?'}@blvl).')';
        }
    }

    my $sql = <<"    SQL";
        SELECT  t.depth,
            u.id AS org_unit,
            sum(
                (SELECT count(cp.id)
                  FROM  $sm_table r
                    JOIN $cn_table cn ON (cn.record = r.source)
                    JOIN $rd_table rd ON (cn.record = rd.record)
                    JOIN $cp_table cp ON (cn.id = cp.call_number)
                        JOIN $cs_table cs ON (cp.status = cs.id)
                        JOIN $cl_table cl ON (cp.location = cl.id)
                    JOIN $descendants a ON (cp.circ_lib = a.id)
                  WHERE r.metarecord = ?
                    AND cn.deleted IS FALSE
                    AND cp.deleted IS FALSE
                    $copies_visible
                    $t_filter
                    $f_filter
                    $b_filter
                )
            ) AS count,
            sum(
                (SELECT count(cp.id)
                  FROM  $sm_table r
                    JOIN $cn_table cn ON (cn.record = r.source)
                    JOIN $rd_table rd ON (cn.record = rd.record)
                    JOIN $cp_table cp ON (cn.id = cp.call_number)
                        JOIN $cs_table cs ON (cp.status = cs.id)
                        JOIN $cl_table cl ON (cp.location = cl.id)
                    JOIN $descendants a ON (cp.circ_lib = a.id)
                  WHERE r.metarecord = ?
                    AND cp.status IN (0,7,12)
                    AND cn.deleted IS FALSE
                    AND cp.deleted IS FALSE
                    $copies_visible
                    $t_filter
                    $f_filter
                    $b_filter
                )
            ) AS available,
            sum(
                (SELECT count(cp.id)
                  FROM  $sm_table r
                    JOIN $cn_table cn ON (cn.record = r.source)
                    JOIN $rd_table rd ON (cn.record = rd.record)
                    JOIN $cp_table cp ON (cn.id = cp.call_number)
                        JOIN $cs_table cs ON (cp.status = cs.id)
                        JOIN $cl_table cl ON (cp.location = cl.id)
                  WHERE r.metarecord = ?
                    AND cn.deleted IS FALSE
                    AND cp.deleted IS FALSE
                    AND cp.opac_visible IS TRUE
                    AND cs.opac_visible IS TRUE
                    AND cl.opac_visible IS TRUE
                    $t_filter
                    $f_filter
                    $b_filter
                )
            ) AS unshadow,
            sum(    
                (SELECT sum(1)
                  FROM  $sm_table r
                        JOIN $br_table br ON (br.id = r.source)
                        JOIN $src_table src ON (src.id = br.source)
                  WHERE r.metarecord = ?
                    AND src.transcendant IS TRUE
                )
            ) AS transcendant

          FROM  $ancestors
          GROUP BY 1,2
    SQL

    my $sth = metabib::metarecord_source_map->db_Main->prepare_cached($sql);
    $sth->execute(  ''.$args{metarecord},
            @types, 
            @forms,
            @blvl,
            ''.$args{metarecord},
            @types, 
            @forms,
            @blvl,
            ''.$args{metarecord},
            @types, 
            @forms,
            @blvl,
            ''.$args{metarecord},
            ''.$args{org_unit}, 
    ); 

    while ( my $row = $sth->fetchrow_hashref ) {
        $client->respond( $row );
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.metabib.metarecord.copy_count',
    no_tz_force => 1,
    method      => 'metarecord_copy_count',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.metabib.metarecord.copy_count.staff',
    no_tz_force => 1,
    method      => 'metarecord_copy_count',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);

sub biblio_multi_search_full_rec {
    my $self   = shift;
    my $client = shift;
    my %args   = @_;

    my $class_join = $args{class_join} || 'AND';
    my $limit      = $args{limit}      || 100;
    my $offset     = $args{offset}     || 0;
    my $sort       = $args{'sort'};
    my $sort_dir   = $args{sort_dir}   || 'DESC';

    my @binds;
    my @selects;

    for my $arg (@{ $args{searches} }) {
        my $term     = $$arg{term};
        my $limiters = $$arg{restrict};

        my ($index_col)  = metabib::full_rec->columns('FTS');
        $index_col ||= 'value';
        my $search_table = metabib::full_rec->table;

        my $fts = OpenILS::Application::Storage::FTS->compile('default' => $term, 'value',"$index_col");

        my $fts_where = $fts->sql_where_clause();
        my @fts_ranks = $fts->fts_rank;

        my $rank = join(' + ', @fts_ranks);

        my @wheres;
        for my $limit (@$limiters) {
            if ($$limit{tag} =~ /^\d+$/ and $$limit{tag} < 10) {
                # MARC control field; mfr.subfield is NULL
                push @wheres, "( tag = ? AND $fts_where )";
                push @binds, $$limit{tag};
                $log->debug("Limiting query using { tag => $$limit{tag} }", DEBUG);
            } else {
                push @wheres, "( tag = ? AND subfield LIKE ? AND $fts_where )";
                push @binds, $$limit{tag}, $$limit{subfield};
                $log->debug("Limiting query using { tag => $$limit{tag}, subfield => $$limit{subfield} }", DEBUG);
            }
        }
        my $where = join(' OR ', @wheres);

        push @selects, "SELECT record, AVG($rank) as sum FROM $search_table WHERE $where GROUP BY record";

    }

    my $descendants = defined($args{depth}) ?
                "actor.org_unit_descendants($args{org_unit}, $args{depth})" :
                "actor.org_unit_descendants($args{org_unit})" ;


    my $metabib_record_descriptor = metabib::record_descriptor->table;
    my $metabib_full_rec = metabib::full_rec->table;
    my $asset_call_number_table = asset::call_number->table;
    my $asset_copy_table = asset::copy->table;
    my $cs_table = config::copy_status->table;
    my $cl_table = asset::copy_location->table;
    my $br_table = biblio::record_entry->table;

    my $cj = undef;
    $cj = 'HAVING COUNT(x.record) = ' . scalar(@selects) if ($class_join eq 'AND');

    my $search_table =
        '(SELECT x.record, sum(x.sum) FROM (('.
            join(') UNION ALL (', @selects).
            ")) x GROUP BY 1 $cj ORDER BY 2 DESC )";

    my $has_vols = 'AND cn.owning_lib = d.id';
    my $has_copies = 'AND cp.call_number = cn.id';
    my $copies_visible = 'AND d.opac_visible IS TRUE AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';

    if ($self->api_name =~ /staff/o) {
        # Staff want to see all copies regardless of visibility
        $copies_visible = '';
        # When searching globally for staff avoid any copy filtering.
        if ((defined $args{depth} && $args{depth} == 0) 
            || $args{org_unit} == $U->get_org_tree->id) {
            $has_copies = '';
            $has_vols   = '';
        }
    }

    my ($t_filter, $f_filter) = ('','');
    my ($a_filter, $l_filter, $lf_filter) = ('','','');

    my $use_rd = 0;
    if (my $a = $args{audience}) {
        $a = [$a] if (!ref($a));
        my @aud = @$a;
            
        $a_filter = ' AND rd.audience IN ('.join(',',map{'?'}@aud).')';
        push @binds, @aud;
        $use_rd = 1;
    }

    if (my $l = $args{language}) {
        $l = [$l] if (!ref($l));
        my @lang = @$l;

        $l_filter = ' AND rd.item_lang IN ('.join(',',map{'?'}@lang).')';
        push @binds, @lang;
        $use_rd = 1;
    }

    if (my $f = $args{lit_form}) {
        $f = [$f] if (!ref($f));
        my @lit_form = @$f;

        $lf_filter = ' AND rd.lit_form IN ('.join(',',map{'?'}@lit_form).')';
        push @binds, @lit_form;
        $use_rd = 1;
    }

    if (my $f = $args{item_form}) {
        $f = [$f] if (!ref($f));
        my @forms = @$f;

        $f_filter = ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
        push @binds, @forms;
        $use_rd = 1;
    }

    if (my $t = $args{item_type}) {
        $t = [$t] if (!ref($t));
        my @types = @$t;

        $t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
        push @binds, @types;
        $use_rd = 1;
    }


    if ($args{format}) {
        my ($t, $f) = split '-', $args{format};
        my @types = split '', $t;
        my @forms = split '', $f;
        if (@types) {
            $t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
            $use_rd = 1;
        }

        if (@forms) {
            $f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
            $use_rd = 1;
        }
        push @binds, @types, @forms;
    }

    my $relevance = 'sum(f.sum)';
    $relevance = 1 if (!$copies_visible);

    my $string_default_sort = 'zzzz';
    $string_default_sort = 'AAAA' if ($sort_dir =~ /^DESC$/i);

    my $number_default_sort = '9999';
    $number_default_sort = '0000' if ($sort_dir =~/^DESC$/i);

    my $rank = $relevance;
    if (lc($sort) eq 'pubdate') {
        $rank = <<"        RANK";
            ( FIRST ((
                SELECT  COALESCE(SUBSTRING(MAX(frp.value) FROM E'\\\\d{4}'), '$number_default_sort')::INT
                  FROM  $metabib_full_rec frp
                  WHERE frp.record = f.record
                    AND frp.tag = '260'
                    AND frp.subfield = 'c'
                  LIMIT 1
            )) )
        RANK
    } elsif (lc($sort) eq 'create_date') {
        $rank = <<"        RANK";
            ( FIRST (( SELECT create_date FROM $br_table rbr WHERE rbr.id = f.record)) )
        RANK
    } elsif (lc($sort) eq 'edit_date') {
        $rank = <<"        RANK";
            ( FIRST (( SELECT edit_date FROM $br_table rbr WHERE rbr.id = f.record)) )
        RANK
    } elsif (lc($sort) =~ /^title/i) {
        $rank = <<"        RANK";
            ( FIRST ((
                SELECT  COALESCE(LTRIM(SUBSTR(MAX(frt.value), COALESCE(SUBSTRING(MAX(frt.ind2) FROM E'\\\\d+'),'0')::INT + 1 )),'$string_default_sort')
                  FROM  $metabib_full_rec frt
                  WHERE frt.record = f.record
                    AND frt.tag = '245'
                    AND frt.subfield = 'a'
                  LIMIT 1
            )) )
        RANK
    } elsif (lc($sort) =~ /^author/i) {
        $rank = <<"        RANK";
            ( FIRST((
                SELECT  COALESCE(LTRIM(MAX(query.value)), '$string_default_sort')
                  FROM  (
                            SELECT fra.value
                            FROM $metabib_full_rec fra
                            WHERE fra.record = f.record
                                AND fra.tag LIKE '1%'
                                AND fra.subfield = 'a'
                            ORDER BY fra.tag::text::int
                            LIMIT 1
                        ) query
            )) )
        RANK
    } else {
        $sort = undef;
    }

    my $rd_join = $use_rd ? "$metabib_record_descriptor rd," : '';
    my $rd_filter = $use_rd ? 'AND rd.record = f.record' : '';

    if ($has_copies) {
        $select = <<"        SQL";
            SELECT  f.record, $relevance, count(DISTINCT cp.id), $rank
            FROM    $search_table f,
                $asset_call_number_table cn,
                $asset_copy_table cp,
                $cs_table cs,
                $cl_table cl,
                $br_table br,
                $rd_join
                $descendants d
            WHERE   br.id = f.record
                AND cn.record = f.record
                AND cp.status = cs.id
                AND cp.location = cl.id
                AND br.deleted IS FALSE
                AND cn.deleted IS FALSE
                AND cp.deleted IS FALSE
                $rd_filter
                $has_vols
                $has_copies
                $copies_visible
                $t_filter
                $f_filter
                $a_filter
                $l_filter
                $lf_filter
            GROUP BY f.record HAVING count(DISTINCT cp.id) > 0
            ORDER BY 4 $sort_dir,3 DESC
        SQL
    } else {
        $select = <<"        SQL";
            SELECT  f.record, 1, 1, $rank
            FROM    $search_table f,
                $rd_join
                $br_table br
            WHERE   br.id = f.record
                AND br.deleted IS FALSE
                $rd_filter
                $t_filter
                $f_filter
                $a_filter
                $l_filter
                $lf_filter
            GROUP BY 1,2,3 
            ORDER BY 4 $sort_dir
        SQL
    }


    $log->debug("Search SQL :: [$select]",DEBUG);

    my $recs = metabib::full_rec->db_Main->selectall_arrayref("$select;", {}, @binds);
    $log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

    my $max = 0;
    $max = 1 if (!@$recs);
    for (@$recs) {
        $max = $$_[1] if ($$_[1] > $max);
    }

    my $count = @$recs;
    for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
        next unless ($$rec[0]);
        my ($rid,$rank,$junk,$skip) = @$rec;
        $client->respond( [$rid, sprintf('%0.3f',$rank/$max), $count] );
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.full_rec.multi_search',
    no_tz_force => 1,
    method      => 'biblio_multi_search_full_rec',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.biblio.full_rec.multi_search.staff',
    no_tz_force => 1,
    method      => 'biblio_multi_search_full_rec',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);

sub search_full_rec {
    my $self = shift;
    my $client = shift;

    my %args = @_;
    
    my $term = $args{term};
    my $limiters = $args{restrict};

    my ($index_col) = metabib::full_rec->columns('FTS');
    $index_col ||= 'value';
    my $search_table = metabib::full_rec->table;

    my $fts = OpenILS::Application::Storage::FTS->compile('default' => $term, 'value',"$index_col");

    my $fts_where = $fts->sql_where_clause();
    my @fts_ranks = $fts->fts_rank;

    my $rank = join(' + ', @fts_ranks);

    my @binds;
    my @wheres;
    for my $limit (@$limiters) {
        if ($$limit{tag} =~ /^\d+$/ and $$limit{tag} < 10) {
            # MARC control field; mfr.subfield is NULL
            push @wheres, "( tag = ? AND $fts_where )";
            push @binds, $$limit{tag};
            $log->debug("Limiting query using { tag => $$limit{tag} }", DEBUG);
        } else {
            push @wheres, "( tag = ? AND subfield LIKE ? AND $fts_where )";
            push @binds, $$limit{tag}, $$limit{subfield};
            $log->debug("Limiting query using { tag => $$limit{tag}, subfield => $$limit{subfield} }", DEBUG);
        }
    }
    my $where = join(' OR ', @wheres);

    my $select = "SELECT record, sum($rank) FROM $search_table WHERE $where GROUP BY 1 ORDER BY 2 DESC;";

    $log->debug("Search SQL :: [$select]",DEBUG);

    my $recs = metabib::full_rec->db_Main->selectall_arrayref($select, {}, @binds);
    $log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

    $client->respond($_) for (@$recs);
    return undef;
}
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.direct.metabib.full_rec.search_fts.value',
    no_tz_force => 1,
    method      => 'search_full_rec',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.storage.direct.metabib.full_rec.search_fts.index_vector',
    no_tz_force => 1,
    method      => 'search_full_rec',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);


# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub search_class_fts {
    my $self = shift;
    my $client = shift;
    my %args = @_;
    
    my $term = $args{term};
    my $ou = $args{org_unit};
    my $ou_type = $args{depth};
    my $limit = $args{limit};
    my $offset = $args{offset};

    my $limit_clause = '';
    my $offset_clause = '';

    $limit_clause = "LIMIT $limit" if (defined $limit and int($limit) > 0);
    $offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

    my (@types,@forms);
    my ($t_filter, $f_filter) = ('','');

    if ($args{format}) {
        my ($t, $f) = split '-', $args{format};
        @types = split '', $t;
        @forms = split '', $f;
        if (@types) {
            $t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
        }

        if (@forms) {
            $f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
        }
    }



    my $descendants = defined($ou_type) ?
                "actor.org_unit_descendants($ou, $ou_type)" :
                "actor.org_unit_descendants($ou)";

    my $class = $self->{cdbi};
    my $search_table = $class->table;

    my $metabib_record_descriptor = metabib::record_descriptor->table;
    my $metabib_metarecord = metabib::metarecord->table;
    my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
    my $asset_call_number_table = asset::call_number->table;
    my $asset_copy_table = asset::copy->table;
    my $cs_table = config::copy_status->table;
    my $cl_table = asset::copy_location->table;

    my ($index_col) = $class->columns('FTS');
    $index_col ||= 'value';

    (my $search_class = $self->api_name) =~ s/.*metabib.(\w+).search_fts.*/$1/o;
    my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $term, 'f.value', "f.$index_col");

    my $fts_where = $fts->sql_where_clause;
    my @fts_ranks = $fts->fts_rank;

    my $rank = join(' + ', @fts_ranks);

    my $has_vols = 'AND cn.owning_lib = d.id';
    my $has_copies = 'AND cp.call_number = cn.id';
    my $copies_visible = 'AND d.opac_visible IS TRUE AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';

    my $visible_count = ', count(DISTINCT cp.id)';
    my $visible_count_test = 'HAVING count(DISTINCT cp.id) > 0';

    if ($self->api_name =~ /staff/o) {
        $copies_visible = '';
        $visible_count_test = '';
        $has_copies = '' if ($ou_type == 0);
        $has_vols = '' if ($ou_type == 0);
    }

    my $rank_calc = <<"    RANK";
        , (SUM( $rank
            * CASE WHEN f.value ILIKE ? THEN 1.2 ELSE 1 END -- phrase order
            * CASE WHEN f.value ILIKE ? THEN 1.5 ELSE 1 END -- first word match
            * CASE WHEN f.value ~* ? THEN 2 ELSE 1 END -- only word match
        )/COUNT(m.source)), MIN(COALESCE(CHAR_LENGTH(f.value),1))
    RANK

    $rank_calc = ',1 , 1' if ($self->api_name =~ /unordered/o);

    if ($copies_visible) {
        $select = <<"        SQL";
            SELECT  m.metarecord $rank_calc $visible_count, CASE WHEN COUNT(DISTINCT m.source) = 1 THEN MAX(m.source) ELSE MAX(0) END
            FROM    $search_table f,
                $metabib_metarecord_source_map_table m,
                $asset_call_number_table cn,
                $asset_copy_table cp,
                $cs_table cs,
                $cl_table cl,
                $metabib_record_descriptor rd,
                $descendants d
            WHERE   $fts_where
                AND m.source = f.source
                AND cn.record = m.source
                AND rd.record = m.source
                AND cp.status = cs.id
                AND cp.location = cl.id
                $has_vols
                $has_copies
                $copies_visible
                $t_filter
                $f_filter
            GROUP BY 1 $visible_count_test
            ORDER BY 2 DESC,3
            $limit_clause $offset_clause
        SQL
    } else {
        $select = <<"        SQL";
            SELECT  m.metarecord $rank_calc, 0, CASE WHEN COUNT(DISTINCT m.source) = 1 THEN MAX(m.source) ELSE MAX(0) END
            FROM    $search_table f,
                $metabib_metarecord_source_map_table m,
                $metabib_record_descriptor rd
            WHERE   $fts_where
                AND m.source = f.source
                AND rd.record = m.source
                $t_filter
                $f_filter
            GROUP BY 1, 4
            ORDER BY 2 DESC,3
            $limit_clause $offset_clause
        SQL
    }

    $log->debug("Field Search SQL :: [$select]",DEBUG);

    my $SQLstring = join('%',$fts->words);
    my $REstring = join('\\s+',$fts->words);
    my $first_word = ($fts->words)[0].'%';
    my $recs = ($self->api_name =~ /unordered/o) ? 
            $class->db_Main->selectall_arrayref($select, {}, @types, @forms) :
            $class->db_Main->selectall_arrayref($select, {},
                '%'.lc($SQLstring).'%',         # phrase order match
                lc($first_word),            # first word match
                '^\\s*'.lc($REstring).'\\s*/?\s*$', # full exact match
                @types, @forms
            );
    
    $log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

    $client->respond($_) for (map { [@$_[0,1,3,4]] } @$recs);
    return undef;
}

for my $class ( qw/title author subject keyword series identifier/ ) {
    __PACKAGE__->register_method(
        api_name    => "open-ils.storage.metabib.$class.search_fts.metarecord",
        no_tz_force => 1,
        method      => 'search_class_fts',
        api_level   => 1,
        stream      => 1,
        cdbi        => "metabib::${class}_field_entry",
        cachable    => 1,
    );
    __PACKAGE__->register_method(
        api_name    => "open-ils.storage.metabib.$class.search_fts.metarecord.unordered",
        no_tz_force => 1,
        method      => 'search_class_fts',
        api_level   => 1,
        stream      => 1,
        cdbi        => "metabib::${class}_field_entry",
        cachable    => 1,
    );
    __PACKAGE__->register_method(
        api_name    => "open-ils.storage.metabib.$class.search_fts.metarecord.staff",
        no_tz_force => 1,
        method      => 'search_class_fts',
        api_level   => 1,
        stream      => 1,
        cdbi        => "metabib::${class}_field_entry",
        cachable    => 1,
    );
    __PACKAGE__->register_method(
        api_name    => "open-ils.storage.metabib.$class.search_fts.metarecord.staff.unordered",
        no_tz_force => 1,
        method      => 'search_class_fts',
        api_level   => 1,
        stream      => 1,
        cdbi        => "metabib::${class}_field_entry",
        cachable    => 1,
    );
}

# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub search_class_fts_count {
    my $self = shift;
    my $client = shift;
    my %args = @_;
    
    my $term = $args{term};
    my $ou = $args{org_unit};
    my $ou_type = $args{depth};
    my $limit = $args{limit} || 100;
    my $offset = $args{offset} || 0;

    my $descendants = defined($ou_type) ?
                "actor.org_unit_descendants($ou, $ou_type)" :
                "actor.org_unit_descendants($ou)";
        
    my (@types,@forms);
    my ($t_filter, $f_filter) = ('','');

    if ($args{format}) {
        my ($t, $f) = split '-', $args{format};
        @types = split '', $t;
        @forms = split '', $f;
        if (@types) {
            $t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
        }

        if (@forms) {
            $f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
        }
    }


    (my $search_class = $self->api_name) =~ s/.*metabib.(\w+).search_fts.*/$1/o;

    my $class = $self->{cdbi};
    my $search_table = $class->table;

    my $metabib_record_descriptor = metabib::record_descriptor->table;
    my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
    my $asset_call_number_table = asset::call_number->table;
    my $asset_copy_table = asset::copy->table;
    my $cs_table = config::copy_status->table;
    my $cl_table = asset::copy_location->table;

    my ($index_col) = $class->columns('FTS');
    $index_col ||= 'value';

    my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $term, 'value',"$index_col");

    my $fts_where = $fts->sql_where_clause;

    my $has_vols = 'AND cn.owning_lib = d.id';
    my $has_copies = 'AND cp.call_number = cn.id';
    my $copies_visible = 'AND d.opac_visible IS TRUE AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';
    if ($self->api_name =~ /staff/o) {
        $copies_visible = '';
        $has_vols = '' if ($ou_type == 0);
        $has_copies = '' if ($ou_type == 0);
    }

    # XXX test an "EXISTS version of descendant checking...
    my $select;
    if ($copies_visible) {
        $select = <<"        SQL";
        SELECT  count(distinct  m.metarecord)
          FROM  $search_table f,
            $metabib_metarecord_source_map_table m,
            $metabib_metarecord_source_map_table mr,
            $asset_call_number_table cn,
            $asset_copy_table cp,
            $cs_table cs,
            $cl_table cl,
            $metabib_record_descriptor rd,
            $descendants d
          WHERE $fts_where
            AND mr.source = f.source
            AND mr.metarecord = m.metarecord
            AND cn.record = m.source
            AND rd.record = m.source
            AND cp.status = cs.id
            AND cp.location = cl.id
            $has_vols
            $has_copies
            $copies_visible
            $t_filter
            $f_filter
        SQL
    } else {
        $select = <<"        SQL";
        SELECT  count(distinct  m.metarecord)
          FROM  $search_table f,
            $metabib_metarecord_source_map_table m,
            $metabib_metarecord_source_map_table mr,
            $metabib_record_descriptor rd
          WHERE $fts_where
            AND mr.source = f.source
            AND mr.metarecord = m.metarecord
            AND rd.record = m.source
            $t_filter
            $f_filter
        SQL
    }

    $log->debug("Field Search Count SQL :: [$select]",DEBUG);

    my $recs = $class->db_Main->selectrow_arrayref($select, {}, @types, @forms)->[0];
    
    $log->debug("Count Search yielded $recs results.",DEBUG);

    return $recs;

}
for my $class ( qw/title author subject keyword series identifier/ ) {
    __PACKAGE__->register_method(
        api_name    => "open-ils.storage.metabib.$class.search_fts.metarecord_count",
        no_tz_force => 1,
        method      => 'search_class_fts_count',
        api_level   => 1,
        stream      => 1,
        cdbi        => "metabib::${class}_field_entry",
        cachable    => 1,
    );
    __PACKAGE__->register_method(
        api_name    => "open-ils.storage.metabib.$class.search_fts.metarecord_count.staff",
        no_tz_force => 1,
        method      => 'search_class_fts_count',
        api_level   => 1,
        stream      => 1,
        cdbi        => "metabib::${class}_field_entry",
        cachable    => 1,
    );
}


# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub postfilter_search_class_fts {
    my $self = shift;
    my $client = shift;
    my %args = @_;
    
    my $term = $args{term};
    my $sort = $args{'sort'};
    my $sort_dir = $args{sort_dir} || 'DESC';
    my $ou = $args{org_unit};
    my $ou_type = $args{depth};
    my $limit = $args{limit} || 10;
    my $visibility_limit = $args{visibility_limit} || 5000;
    my $offset = $args{offset} || 0;

    my $outer_limit = 1000;

    my $limit_clause = '';
    my $offset_clause = '';

    $limit_clause = "LIMIT $outer_limit";
    $offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

    my (@types,@forms,@lang,@aud,@lit_form);
    my ($t_filter, $f_filter) = ('','');
    my ($a_filter, $l_filter, $lf_filter) = ('','','');
    my ($ot_filter, $of_filter) = ('','');
    my ($oa_filter, $ol_filter, $olf_filter) = ('','','');

    if (my $a = $args{audience}) {
        $a = [$a] if (!ref($a));
        @aud = @$a;
            
        $a_filter = ' AND rd.audience IN ('.join(',',map{'?'}@aud).')';
        $oa_filter = ' AND ord.audience IN ('.join(',',map{'?'}@aud).')';
    }

    if (my $l = $args{language}) {
        $l = [$l] if (!ref($l));
        @lang = @$l;

        $l_filter = ' AND rd.item_lang IN ('.join(',',map{'?'}@lang).')';
        $ol_filter = ' AND ord.item_lang IN ('.join(',',map{'?'}@lang).')';
    }

    if (my $f = $args{lit_form}) {
        $f = [$f] if (!ref($f));
        @lit_form = @$f;

        $lf_filter = ' AND rd.lit_form IN ('.join(',',map{'?'}@lit_form).')';
        $olf_filter = ' AND ord.lit_form IN ('.join(',',map{'?'}@lit_form).')';
    }

    if ($args{format}) {
        my ($t, $f) = split '-', $args{format};
        @types = split '', $t;
        @forms = split '', $f;
        if (@types) {
            $t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
            $ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
        }

        if (@forms) {
            $f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
            $of_filter .= ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
        }
    }


    my $descendants = defined($ou_type) ?
                "actor.org_unit_descendants($ou, $ou_type)" :
                "actor.org_unit_descendants($ou)";

    my $class = $self->{cdbi};
    my $search_table = $class->table;

    my $metabib_full_rec = metabib::full_rec->table;
    my $metabib_record_descriptor = metabib::record_descriptor->table;
    my $metabib_metarecord = metabib::metarecord->table;
    my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
    my $asset_call_number_table = asset::call_number->table;
    my $asset_copy_table = asset::copy->table;
    my $cs_table = config::copy_status->table;
    my $cl_table = asset::copy_location->table;
    my $br_table = biblio::record_entry->table;

    my ($index_col) = $class->columns('FTS');
    $index_col ||= 'value';

    (my $search_class = $self->api_name) =~ s/.*metabib.(\w+).post_filter.*/$1/o;

    my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $term, 'f.value', "f.$index_col");

    my $SQLstring = join('%',map { lc($_) } $fts->words);
    my $REstring = '^' . join('\s+',map { lc($_) } $fts->words) . '\W*$';
    my $first_word = lc(($fts->words)[0]).'%';

    my $fts_where = $fts->sql_where_clause;
    my @fts_ranks = $fts->fts_rank;

    my %bonus = ();
    $bonus{'metabib::identifier_field_entry'} =
        $bonus{'metabib::keyword_field_entry'} = [
            { 'CASE WHEN f.value ILIKE ? THEN 1.2 ELSE 1 END' => $SQLstring }
        ];

    $bonus{'metabib::title_field_entry'} =
        $bonus{'metabib::series_field_entry'} = [
            { 'CASE WHEN f.value ILIKE ? THEN 1.5 ELSE 1 END' => $first_word },
            { 'CASE WHEN f.value ~* ? THEN 2 ELSE 1 END' => $REstring },
            @{ $bonus{'metabib::keyword_field_entry'} }
        ];

    my $bonus_list = join ' * ', map { keys %$_ } @{ $bonus{$class} };
    $bonus_list ||= '1';

    my @bonus_values = map { values %$_ } @{ $bonus{$class} };

    my $relevance = join(' + ', @fts_ranks);
    $relevance = <<"    RANK";
            (SUM( ( $relevance )  * ( $bonus_list ) )/COUNT(m.source))
    RANK

    my $string_default_sort = 'zzzz';
    $string_default_sort = 'AAAA' if ($sort_dir eq 'DESC');

    my $number_default_sort = '9999';
    $number_default_sort = '0000' if ($sort_dir eq 'DESC');

    my $rank = $relevance;
    if (lc($sort) eq 'pubdate') {
        $rank = <<"        RANK";
            ( FIRST ((
                SELECT  COALESCE(SUBSTRING(frp.value FROM E'\\\\d+'),'$number_default_sort')::INT
                  FROM  $metabib_full_rec frp
                  WHERE frp.record = mr.master_record
                    AND frp.tag = '260'
                    AND frp.subfield = 'c'
                  LIMIT 1
            )) )
        RANK
    } elsif (lc($sort) eq 'create_date') {
        $rank = <<"        RANK";
            ( FIRST (( SELECT create_date FROM $br_table rbr WHERE rbr.id = mr.master_record)) )
        RANK
    } elsif (lc($sort) eq 'edit_date') {
        $rank = <<"        RANK";
            ( FIRST (( SELECT edit_date FROM $br_table rbr WHERE rbr.id = mr.master_record)) )
        RANK
    } elsif (lc($sort) eq 'title') {
        $rank = <<"        RANK";
            ( FIRST ((
                SELECT  COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'$string_default_sort')
                  FROM  $metabib_full_rec frt
                  WHERE frt.record = mr.master_record
                    AND frt.tag = '245'
                    AND frt.subfield = 'a'
                  LIMIT 1
            )) )
        RANK
    } elsif (lc($sort) eq 'author') {
        $rank = <<"        RANK";
            ( FIRST((
                SELECT  COALESCE(LTRIM(fra.value),'$string_default_sort')
                  FROM  $metabib_full_rec fra
                  WHERE fra.record = mr.master_record
                    AND fra.tag LIKE '1%'
                    AND fra.subfield = 'a'
                  ORDER BY fra.tag::text::int
                  LIMIT 1
            )) )
        RANK
    } else {
        $sort = undef;
    }

    my $select = <<"    SQL";
        SELECT  m.metarecord,
            $relevance,
            CASE WHEN COUNT(DISTINCT smrs.source) = 1 THEN MIN(m.source) ELSE 0 END,
            $rank
        FROM    $search_table f,
            $metabib_metarecord_source_map_table m,
            $metabib_metarecord_source_map_table smrs,
            $metabib_metarecord mr,
            $metabib_record_descriptor rd
        WHERE   $fts_where
            AND smrs.metarecord = mr.id
            AND m.source = f.source
            AND m.metarecord = mr.id
            AND rd.record = smrs.source
            $t_filter
            $f_filter
            $a_filter
            $l_filter
            $lf_filter
        GROUP BY m.metarecord
        ORDER BY 4 $sort_dir, MIN(COALESCE(CHAR_LENGTH(f.value),1))
        LIMIT $visibility_limit
    SQL

    if (0) {
        $select = <<"        SQL";

            SELECT  DISTINCT s.*
              FROM  $asset_call_number_table cn,
                $metabib_metarecord_source_map_table mrs,
                $asset_copy_table cp,
                $cs_table cs,
                $cl_table cl,
                $br_table br,
                $descendants d,
                $metabib_record_descriptor ord,
                ($select) s
              WHERE mrs.metarecord = s.metarecord
                AND br.id = mrs.source
                AND cn.record = mrs.source
                AND cp.status = cs.id
                AND cp.location = cl.id
                AND cn.owning_lib = d.id
                AND cp.call_number = cn.id
                AND cp.opac_visible IS TRUE
                AND cs.opac_visible IS TRUE
                AND cl.opac_visible IS TRUE
                AND d.opac_visible IS TRUE
                AND br.active IS TRUE
                AND br.deleted IS FALSE
                AND ord.record = mrs.source
                $ot_filter
                $of_filter
                $oa_filter
                $ol_filter
                $olf_filter
              ORDER BY 4 $sort_dir
        SQL
    } elsif ($self->api_name !~ /staff/o) {
        $select = <<"        SQL";

            SELECT  DISTINCT s.*
              FROM  ($select) s
              WHERE EXISTS (
                SELECT  1
                  FROM  $asset_call_number_table cn,
                    $metabib_metarecord_source_map_table mrs,
                    $asset_copy_table cp,
                    $cs_table cs,
                    $cl_table cl,
                    $br_table br,
                    $descendants d,
                    $metabib_record_descriptor ord
                
                  WHERE mrs.metarecord = s.metarecord
                    AND br.id = mrs.source
                    AND cn.record = mrs.source
                    AND cp.status = cs.id
                    AND cp.location = cl.id
                    AND cp.circ_lib = d.id
                    AND cp.call_number = cn.id
                    AND cp.opac_visible IS TRUE
                    AND cs.opac_visible IS TRUE
                    AND cl.opac_visible IS TRUE
                    AND d.opac_visible IS TRUE
                    AND br.active IS TRUE
                    AND br.deleted IS FALSE
                    AND ord.record = mrs.source
                    $ot_filter
                    $of_filter
                    $oa_filter
                    $ol_filter
                    $olf_filter
                  LIMIT 1
                )
              ORDER BY 4 $sort_dir
        SQL
    } else {
        $select = <<"        SQL";

            SELECT  DISTINCT s.*
              FROM  ($select) s
              WHERE EXISTS (
                SELECT  1
                  FROM  $asset_call_number_table cn,
                    $asset_copy_table cp,
                    $metabib_metarecord_source_map_table mrs,
                    $br_table br,
                    $descendants d,
                    $metabib_record_descriptor ord
                
                  WHERE mrs.metarecord = s.metarecord
                    AND br.id = mrs.source
                    AND cn.record = mrs.source
                    AND cn.id = cp.call_number
                    AND br.deleted IS FALSE
                    AND cn.deleted IS FALSE
                    AND ord.record = mrs.source
                    AND (   cn.owning_lib = d.id
                        OR (    cp.circ_lib = d.id
                            AND cp.deleted IS FALSE
                        )
                    )
                    $ot_filter
                    $of_filter
                    $oa_filter
                    $ol_filter
                    $olf_filter
                  LIMIT 1
                )
                OR NOT EXISTS (
                SELECT  1
                  FROM  $asset_call_number_table cn,
                    $metabib_metarecord_source_map_table mrs,
                    $metabib_record_descriptor ord
                  WHERE mrs.metarecord = s.metarecord
                    AND cn.record = mrs.source
                    AND ord.record = mrs.source
                    $ot_filter
                    $of_filter
                    $oa_filter
                    $ol_filter
                    $olf_filter
                  LIMIT 1
                )
              ORDER BY 4 $sort_dir
        SQL
    }


    $log->debug("Field Search SQL :: [$select]",DEBUG);

    my $recs = $class->db_Main->selectall_arrayref(
            $select, {},
            (@bonus_values > 0 ? @bonus_values : () ),
            ( (!$sort && @bonus_values > 0) ? @bonus_values : () ),
            @types, @forms, @aud, @lang, @lit_form,
            @types, @forms, @aud, @lang, @lit_form,
            ($self->api_name =~ /staff/o ? (@types, @forms, @aud, @lang, @lit_form) : () ) );
    
    $log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

    my $max = 0;
    $max = 1 if (!@$recs);
    for (@$recs) {
        $max = $$_[1] if ($$_[1] > $max);
    }

    my $count = scalar(@$recs);
    for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
        my ($mrid,$rank,$skip) = @$rec;
        $client->respond( [$mrid, sprintf('%0.3f',$rank/$max), $skip, $count] );
    }
    return undef;
}

for my $class ( qw/title author subject keyword series identifier/ ) {
    __PACKAGE__->register_method(
        api_name    => "open-ils.storage.metabib.$class.post_filter.search_fts.metarecord",
        no_tz_force => 1,
        method      => 'postfilter_search_class_fts',
        api_level   => 1,
        stream      => 1,
        cdbi        => "metabib::${class}_field_entry",
        cachable    => 1,
    );
    __PACKAGE__->register_method(
        api_name    => "open-ils.storage.metabib.$class.post_filter.search_fts.metarecord.staff",
        no_tz_force => 1,
        method      => 'postfilter_search_class_fts',
        api_level   => 1,
        stream      => 1,
        cdbi        => "metabib::${class}_field_entry",
        cachable    => 1,
    );
}



my $_cdbi = {   title   => "metabib::title_field_entry",
        author  => "metabib::author_field_entry",
        subject => "metabib::subject_field_entry",
        keyword => "metabib::keyword_field_entry",
        series  => "metabib::series_field_entry",
        identifier  => "metabib::identifier_field_entry",
};

# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub postfilter_search_multi_class_fts {
    my $self   = shift;
    my $client = shift;
    my %args   = @_;
    
    my $sort             = $args{'sort'};
    my $sort_dir         = $args{sort_dir} || 'DESC';
    my $ou               = $args{org_unit};
    my $ou_type          = $args{depth};
    my $limit            = $args{limit}  || 10;
    my $offset           = $args{offset} ||  0;
    my $visibility_limit = $args{visibility_limit} || 5000;

    if (!$ou) {
        $ou = actor::org_unit->search( { parent_ou => undef } )->next->id;
    }

    if (!defined($args{org_unit})) {
        die "No target organizational unit passed to ".$self->api_name;
    }

    if (! scalar( keys %{$args{searches}} )) {
        die "No search arguments were passed to ".$self->api_name;
    }

    my $outer_limit = 1000;

    my $limit_clause  = '';
    my $offset_clause = '';

    $limit_clause  = "LIMIT $outer_limit";
    $offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

    my ($avail_filter,@types,@forms,@lang,@aud,@lit_form,@vformats) = ('');
    my ($t_filter,   $f_filter,   $v_filter) = ('','','');
    my ($a_filter,   $l_filter,  $lf_filter) = ('','','');
    my ($ot_filter, $of_filter,  $ov_filter) = ('','','');
    my ($oa_filter, $ol_filter, $olf_filter) = ('','','');

    if ($args{available}) {
        $avail_filter = ' AND cp.status IN (0,7,12)';
    }

    if (my $a = $args{audience}) {
        $a = [$a] if (!ref($a));
        @aud = @$a;
            
        $a_filter  = ' AND  rd.audience IN ('.join(',',map{'?'}@aud).')';
        $oa_filter = ' AND ord.audience IN ('.join(',',map{'?'}@aud).')';
    }

    if (my $l = $args{language}) {
        $l = [$l] if (!ref($l));
        @lang = @$l;

        $l_filter  = ' AND  rd.item_lang IN ('.join(',',map{'?'}@lang).')';
        $ol_filter = ' AND ord.item_lang IN ('.join(',',map{'?'}@lang).')';
    }

    if (my $f = $args{lit_form}) {
        $f = [$f] if (!ref($f));
        @lit_form = @$f;

        $lf_filter  = ' AND  rd.lit_form IN ('.join(',',map{'?'}@lit_form).')';
        $olf_filter = ' AND ord.lit_form IN ('.join(',',map{'?'}@lit_form).')';
    }

    if (my $f = $args{item_form}) {
        $f = [$f] if (!ref($f));
        @forms = @$f;

        $f_filter  = ' AND  rd.item_form IN ('.join(',',map{'?'}@forms).')';
        $of_filter = ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
    }

    if (my $t = $args{item_type}) {
        $t = [$t] if (!ref($t));
        @types = @$t;

        $t_filter  = ' AND  rd.item_type IN ('.join(',',map{'?'}@types).')';
        $ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
    }

    if (my $v = $args{vr_format}) {
        $v = [$v] if (!ref($v));
        @vformats = @$v;

        $v_filter  = ' AND  rd.vr_format IN ('.join(',',map{'?'}@vformats).')';
        $ov_filter = ' AND ord.vr_format IN ('.join(',',map{'?'}@vformats).')';
    }


    # XXX legacy format and item type support
    if ($args{format}) {
        my ($t, $f) = split '-', $args{format};
        @types = split '', $t;
        @forms = split '', $f;
        if (@types) {
            $t_filter  = ' AND  rd.item_type IN ('.join(',',map{'?'}@types).')';
            $ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
        }

        if (@forms) {
            $f_filter  .= ' AND  rd.item_form IN ('.join(',',map{'?'}@forms).')';
            $of_filter .= ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
        }
    }



    my $descendants = defined($ou_type) ?
                "actor.org_unit_descendants($ou, $ou_type)" :
                "actor.org_unit_descendants($ou)";

    my $search_table_list = '';
    my $fts_list          = '';
    my $join_table_list   = '';
    my @rank_list;

    my $field_table = config::metabib_field->table;

    my @bonus_lists;
    my @bonus_values;
    my $prev_search_group;
    my $curr_search_group;
    my $search_class;
    my $search_field;
    my $metabib_field;
    for my $search_group (sort keys %{$args{searches}}) {
        (my $search_group_name = $search_group) =~ s/\|/_/gso;
        ($search_class,$search_field) = split /\|/, $search_group;
        $log->debug("Searching class [$search_class] and field [$search_field]",DEBUG);

        if ($search_field) {
            unless ( $metabib_field = config::metabib_field->search( field_class => $search_class, name => $search_field )->next ) {
                $log->warn("Requested class [$search_class] or field [$search_field] does not exist!");
                return undef;
            }
        }

        $prev_search_group = $curr_search_group if ($curr_search_group);

        $curr_search_group = $search_group_name;

        my $class = $_cdbi->{$search_class};
        my $search_table = $class->table;

        my ($index_col) = $class->columns('FTS');
        $index_col ||= 'value';

        
        my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $args{searches}{$search_group}{term}, $search_group_name.'.value', "$search_group_name.$index_col");

        my $fts_where = $fts->sql_where_clause;
        my @fts_ranks = $fts->fts_rank;

        my $SQLstring = join('%',map { lc($_) } $fts->words);
        my $REstring = '^' . join('\s+',map { lc($_) } $fts->words) . '\W*$';
        my $first_word = lc(($fts->words)[0]).'%';

        $_.=" * (SELECT weight FROM $field_table WHERE $search_group_name.field = id)" for (@fts_ranks);
        my $rank = join(' + ', @fts_ranks);

        my %bonus = ();
        $bonus{'keyword'} = [ { "CASE WHEN $search_group_name.value LIKE ? THEN 10 ELSE 1 END" => $SQLstring } ];
        $bonus{'author'}  = [ { "CASE WHEN $search_group_name.value ILIKE ? THEN 10 ELSE 1 END" => $first_word } ];

        $bonus{'series'} = [
            { "CASE WHEN $search_group_name.value LIKE ? THEN 1.5 ELSE 1 END" => $first_word },
            { "CASE WHEN $search_group_name.value ~ ? THEN 20 ELSE 1 END" => $REstring },
        ];

        $bonus{'title'} = [ @{ $bonus{'series'} }, @{ $bonus{'keyword'} } ];

        my $bonus_list = join ' * ', map { keys %$_ } @{ $bonus{$search_class} };
        $bonus_list ||= '1';

        push @bonus_lists, $bonus_list;
        push @bonus_values, map { values %$_ } @{ $bonus{$search_class} };


        #---------------------

        $search_table_list .= "$search_table $search_group_name, ";
        push @rank_list,$rank;
        $fts_list .= " AND $fts_where AND m.source = $search_group_name.source";

        if ($metabib_field) {
            $join_table_list .= " AND $search_group_name.field = " . $metabib_field->id;
            $metabib_field = undef;
        }

        if ($prev_search_group) {
            $join_table_list .= " AND $prev_search_group.source = $curr_search_group.source";
        }
    }

    my $metabib_record_descriptor = metabib::record_descriptor->table;
    my $metabib_full_rec = metabib::full_rec->table;
    my $metabib_metarecord = metabib::metarecord->table;
    my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
    my $asset_call_number_table = asset::call_number->table;
    my $asset_copy_table = asset::copy->table;
    my $cs_table = config::copy_status->table;
    my $cl_table = asset::copy_location->table;
    my $br_table = biblio::record_entry->table;
    my $source_table = config::bib_source->table;

    my $bonuses = join (' * ', @bonus_lists);
    my $relevance = join (' + ', @rank_list);
    $relevance = "SUM( ($relevance) * ($bonuses) )/COUNT(DISTINCT smrs.source)";

    my $string_default_sort = 'zzzz';
    $string_default_sort = 'AAAA' if ($sort_dir eq 'DESC');

    my $number_default_sort = '9999';
    $number_default_sort = '0000' if ($sort_dir eq 'DESC');



    my $secondary_sort = <<"    SORT";
        ( FIRST ((
            SELECT  COALESCE(LTRIM(SUBSTR( sfrt.value, COALESCE(SUBSTRING(sfrt.ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'$string_default_sort')
              FROM  $metabib_full_rec sfrt,
                $metabib_metarecord mr
              WHERE sfrt.record = mr.master_record
                AND sfrt.tag = '245'
                AND sfrt.subfield = 'a'
              LIMIT 1
        )) )
    SORT

    my $rank = $relevance;
    if (lc($sort) eq 'pubdate') {
        $rank = <<"        RANK";
            ( FIRST ((
                SELECT  COALESCE(SUBSTRING(frp.value FROM E'\\\\d+'),'$number_default_sort')::INT
                  FROM  $metabib_full_rec frp
                  WHERE frp.record = mr.master_record
                    AND frp.tag = '260'
                    AND frp.subfield = 'c'
                  LIMIT 1
            )) )
        RANK
    } elsif (lc($sort) eq 'create_date') {
        $rank = <<"        RANK";
            ( FIRST (( SELECT create_date FROM $br_table rbr WHERE rbr.id = mr.master_record)) )
        RANK
    } elsif (lc($sort) eq 'edit_date') {
        $rank = <<"        RANK";
            ( FIRST (( SELECT edit_date FROM $br_table rbr WHERE rbr.id = mr.master_record)) )
        RANK
    } elsif (lc($sort) eq 'title') {
        $rank = <<"        RANK";
            ( FIRST ((
                SELECT  COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'$string_default_sort')
                  FROM  $metabib_full_rec frt
                  WHERE frt.record = mr.master_record
                    AND frt.tag = '245'
                    AND frt.subfield = 'a'
                  LIMIT 1
            )) )
        RANK
        $secondary_sort = <<"        SORT";
            ( FIRST ((
                SELECT  COALESCE(SUBSTRING(sfrp.value FROM E'\\\\d+'),'$number_default_sort')::INT
                  FROM  $metabib_full_rec sfrp
                  WHERE sfrp.record = mr.master_record
                    AND sfrp.tag = '260'
                    AND sfrp.subfield = 'c'
                  LIMIT 1
            )) )
        SORT
    } elsif (lc($sort) eq 'author') {
        $rank = <<"        RANK";
            ( FIRST((
                SELECT  COALESCE(LTRIM(fra.value),'$string_default_sort')
                  FROM  $metabib_full_rec fra
                  WHERE fra.record = mr.master_record
                    AND fra.tag LIKE '1%'
                    AND fra.subfield = 'a'
                  ORDER BY fra.tag::text::int
                  LIMIT 1
            )) )
        RANK
    } else {
        push @bonus_values, @bonus_values;
        $sort = undef;
    }


    my $select = <<"    SQL";
        SELECT  m.metarecord,
            $relevance,
            CASE WHEN COUNT(DISTINCT smrs.source) = 1 THEN FIRST(m.source) ELSE 0 END,
            $rank,
            $secondary_sort
        FROM    $search_table_list
            $metabib_metarecord mr,
            $metabib_metarecord_source_map_table m,
            $metabib_metarecord_source_map_table smrs
        WHERE   m.metarecord = smrs.metarecord 
            AND mr.id = m.metarecord
            $fts_list
            $join_table_list
        GROUP BY m.metarecord
        -- ORDER BY 4 $sort_dir
        LIMIT $visibility_limit
    SQL

    if ($self->api_name !~ /staff/o) {
        $select = <<"        SQL";

            SELECT  s.*
              FROM  ($select) s
              WHERE EXISTS (
                SELECT  1
                  FROM  $asset_call_number_table cn,
                    $metabib_metarecord_source_map_table mrs,
                    $asset_copy_table cp,
                    $cs_table cs,
                    $cl_table cl,
                    $br_table br,
                    $descendants d,
                    $metabib_record_descriptor ord
                  WHERE mrs.metarecord = s.metarecord
                    AND br.id = mrs.source
                    AND cn.record = mrs.source
                    AND cp.status = cs.id
                    AND cp.location = cl.id
                    AND cp.circ_lib = d.id
                    AND cp.call_number = cn.id
                    AND cp.opac_visible IS TRUE
                    AND cs.opac_visible IS TRUE
                    AND cl.opac_visible IS TRUE
                    AND d.opac_visible IS TRUE
                    AND br.active IS TRUE
                    AND br.deleted IS FALSE
                    AND cp.deleted IS FALSE
                    AND cn.deleted IS FALSE
                    AND ord.record = mrs.source
                    $ot_filter
                    $of_filter
                    $ov_filter
                    $oa_filter
                    $ol_filter
                    $olf_filter
                    $avail_filter
                  LIMIT 1
                )
                OR EXISTS (
                SELECT  1
                  FROM  $br_table br,
                    $metabib_metarecord_source_map_table mrs,
                    $metabib_record_descriptor ord,
                    $source_table src
                  WHERE mrs.metarecord = s.metarecord
                    AND ord.record = mrs.source
                    AND br.id = mrs.source
                    AND br.source = src.id
                    AND src.transcendant IS TRUE
                    $ot_filter
                    $of_filter
                    $ov_filter
                    $oa_filter
                    $ol_filter
                    $olf_filter
                )
              ORDER BY 4 $sort_dir, 5
        SQL
    } else {
        $select = <<"        SQL";

            SELECT  DISTINCT s.*
              FROM  ($select) s,
                $metabib_metarecord_source_map_table omrs,
                $metabib_record_descriptor ord
              WHERE omrs.metarecord = s.metarecord
                AND ord.record = omrs.source
                AND (   EXISTS (
                        SELECT  1
                          FROM  $asset_call_number_table cn,
                            $asset_copy_table cp,
                            $descendants d,
                            $br_table br
                          WHERE br.id = omrs.source
                            AND cn.record = omrs.source
                            AND br.deleted IS FALSE
                            AND cn.deleted IS FALSE
                            AND cp.call_number = cn.id
                            AND (   cn.owning_lib = d.id
                                OR (    cp.circ_lib = d.id
                                    AND cp.deleted IS FALSE
                                )
                            )
                            $avail_filter
                          LIMIT 1
                    )
                    OR NOT EXISTS (
                        SELECT  1
                          FROM  $asset_call_number_table cn
                          WHERE cn.record = omrs.source
                            AND cn.deleted IS FALSE
                          LIMIT 1
                    )
                    OR EXISTS (
                    SELECT  1
                      FROM  $br_table br,
                        $metabib_metarecord_source_map_table mrs,
                        $metabib_record_descriptor ord,
                        $source_table src
                      WHERE mrs.metarecord = s.metarecord
                        AND br.id = mrs.source
                        AND br.source = src.id
                        AND src.transcendant IS TRUE
                        $ot_filter
                        $of_filter
                        $ov_filter
                        $oa_filter
                        $ol_filter
                        $olf_filter
                    )
                )
                $ot_filter
                $of_filter
                $ov_filter
                $oa_filter
                $ol_filter
                $olf_filter

              ORDER BY 4 $sort_dir, 5
        SQL
    }


    $log->debug("Field Search SQL :: [$select]",DEBUG);

    my $recs = $_cdbi->{title}->db_Main->selectall_arrayref(
            $select, {},
            @bonus_values,
            @types, @forms, @vformats, @aud, @lang, @lit_form,
            @types, @forms, @vformats, @aud, @lang, @lit_form,
            # ($self->api_name =~ /staff/o ? (@types, @forms, @aud, @lang, @lit_form) : () )
    );
    
    $log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

    my $max = 0;
    $max = 1 if (!@$recs);
    for (@$recs) {
        $max = $$_[1] if ($$_[1] > $max);
    }

    my $count = scalar(@$recs);
    for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
        next unless ($$rec[0]);
        my ($mrid,$rank,$skip) = @$rec;
        $client->respond( [$mrid, sprintf('%0.3f',$rank/$max), $skip, $count] );
    }
    return undef;
}

__PACKAGE__->register_method(
    api_name    => "open-ils.storage.metabib.post_filter.multiclass.search_fts.metarecord",
    no_tz_force => 1,
    method      => 'postfilter_search_multi_class_fts',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.metabib.post_filter.multiclass.search_fts.metarecord.staff",
    no_tz_force => 1,
    method      => 'postfilter_search_multi_class_fts',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);

__PACKAGE__->register_method(
    api_name    => "open-ils.storage.metabib.multiclass.search_fts",
    no_tz_force => 1,
    method      => 'postfilter_search_multi_class_fts',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.metabib.multiclass.search_fts.staff",
    no_tz_force => 1,
    method      => 'postfilter_search_multi_class_fts',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);

# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub biblio_search_multi_class_fts {
    my $self = shift;
    my $client = shift;
    my %args = @_;
    
    my $sort             = $args{'sort'};
    my $sort_dir         = $args{sort_dir} || 'DESC';
    my $ou               = $args{org_unit};
    my $ou_type          = $args{depth};
    my $limit            = $args{limit}  || 10;
    my $offset           = $args{offset} ||  0;
    my $pref_lang        = $args{preferred_language} || 'eng';
    my $visibility_limit = $args{visibility_limit}  || 5000;

    if (!$ou) {
        $ou = actor::org_unit->search( { parent_ou => undef } )->next->id;
    }

    if (! scalar( keys %{$args{searches}} )) {
        die "No search arguments were passed to ".$self->api_name;
    }

    my $outer_limit = 1000;

    my $limit_clause  = '';
    my $offset_clause = '';

    $limit_clause  = "LIMIT $outer_limit";
    $offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

    my ($avail_filter,@types,@forms,@lang,@aud,@lit_form,@vformats) = ('');
    my ($t_filter,   $f_filter,   $v_filter) = ('','','');
    my ($a_filter,   $l_filter,  $lf_filter) = ('','','');
    my ($ot_filter, $of_filter,  $ov_filter) = ('','','');
    my ($oa_filter, $ol_filter, $olf_filter) = ('','','');

    if ($args{available}) {
        $avail_filter = ' AND cp.status IN (0,7,12)';
    }

    if (my $a = $args{audience}) {
        $a = [$a] if (!ref($a));
        @aud = @$a;
            
        $a_filter  = ' AND rd.audience  IN ('.join(',',map{'?'}@aud).')';
        $oa_filter = ' AND ord.audience IN ('.join(',',map{'?'}@aud).')';
    }

    if (my $l = $args{language}) {
        $l = [$l] if (!ref($l));
        @lang = @$l;

        $l_filter  = ' AND rd.item_lang  IN ('.join(',',map{'?'}@lang).')';
        $ol_filter = ' AND ord.item_lang IN ('.join(',',map{'?'}@lang).')';
    }

    if (my $f = $args{lit_form}) {
        $f = [$f] if (!ref($f));
        @lit_form = @$f;

        $lf_filter  = ' AND rd.lit_form  IN ('.join(',',map{'?'}@lit_form).')';
        $olf_filter = ' AND ord.lit_form IN ('.join(',',map{'?'}@lit_form).')';
    }

    if (my $f = $args{item_form}) {
        $f = [$f] if (!ref($f));
        @forms = @$f;

        $f_filter  = ' AND rd.item_form  IN ('.join(',',map{'?'}@forms).')';
        $of_filter = ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
    }

    if (my $t = $args{item_type}) {
        $t = [$t] if (!ref($t));
        @types = @$t;

        $t_filter  = ' AND rd.item_type  IN ('.join(',',map{'?'}@types).')';
        $ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
    }

    if (my $v = $args{vr_format}) {
        $v = [$v] if (!ref($v));
        @vformats = @$v;

        $v_filter  = ' AND rd.vr_format  IN ('.join(',',map{'?'}@vformats).')';
        $ov_filter = ' AND ord.vr_format IN ('.join(',',map{'?'}@vformats).')';
    }

    # XXX legacy format and item type support
    if ($args{format}) {
        my ($t, $f) = split '-', $args{format};
        @types = split '', $t;
        @forms = split '', $f;
        if (@types) {
            $t_filter  = ' AND rd.item_type  IN ('.join(',',map{'?'}@types).')';
            $ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
        }

        if (@forms) {
            $f_filter  .= ' AND rd.item_form  IN ('.join(',',map{'?'}@forms).')';
            $of_filter .= ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
        }
    }


    my $descendants = defined($ou_type) ?
                "actor.org_unit_descendants($ou, $ou_type)" :
                "actor.org_unit_descendants($ou)";

    my $search_table_list = '';
    my $fts_list = '';
    my $join_table_list = '';
    my @rank_list;

    my $field_table = config::metabib_field->table;

    my @bonus_lists;
    my @bonus_values;
    my $prev_search_group;
    my $curr_search_group;
    my $search_class;
    my $search_field;
    my $metabib_field;
    for my $search_group (sort keys %{$args{searches}}) {
        (my $search_group_name = $search_group) =~ s/\|/_/gso;
        ($search_class,$search_field) = split /\|/, $search_group;
        $log->debug("Searching class [$search_class] and field [$search_field]",DEBUG);

        if ($search_field) {
            unless ( $metabib_field = config::metabib_field->search( field_class => $search_class, name => $search_field )->next ) {
                $log->warn("Requested class [$search_class] or field [$search_field] does not exist!");
                return undef;
            }
        }

        $prev_search_group = $curr_search_group if ($curr_search_group);

        $curr_search_group = $search_group_name;

        my $class = $_cdbi->{$search_class};
        my $search_table = $class->table;

        my ($index_col) = $class->columns('FTS');
        $index_col ||= 'value';

        
        my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $args{searches}{$search_group}{term}, $search_group_name.'.value', "$search_group_name.$index_col");

        my $fts_where = $fts->sql_where_clause;
        my @fts_ranks = $fts->fts_rank;

        my $SQLstring = join('%',map { lc($_) } $fts->words) .'%';
        my $REstring = '^' . join('\s+',map { lc($_) } $fts->words) . '\W*$';
        my $first_word = lc(($fts->words)[0]).'%';

        $_.=" * (SELECT weight FROM $field_table WHERE $search_group_name.field = id)" for (@fts_ranks);
        my $rank = join('  + ', @fts_ranks);

        my %bonus = ();
        $bonus{'subject'} = [];
        $bonus{'author'}  = [ { "CASE WHEN $search_group_name.value ILIKE ? THEN 1.5 ELSE 1 END" => $first_word } ];

        $bonus{'keyword'} = [ { "CASE WHEN $search_group_name.value ILIKE ? THEN 10 ELSE 1 END" => $SQLstring } ];

        $bonus{'series'} = [
            { "CASE WHEN $search_group_name.value ILIKE ? THEN 1.5 ELSE 1 END" => $first_word },
            { "CASE WHEN $search_group_name.value ~ ? THEN 20 ELSE 1 END" => $REstring },
        ];

        $bonus{'title'} = [ @{ $bonus{'series'} }, @{ $bonus{'keyword'} } ];

        if ($pref_lang) {
            push @{ $bonus{'title'}   }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
            push @{ $bonus{'author'}  }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
            push @{ $bonus{'subject'} }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
            push @{ $bonus{'keyword'} }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
            push @{ $bonus{'series'}  }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
        }

        my $bonus_list = join ' * ', map { keys %$_ } @{ $bonus{$search_class} };
        $bonus_list ||= '1';

        push @bonus_lists, $bonus_list;
        push @bonus_values, map { values %$_ } @{ $bonus{$search_class} };

        #---------------------

        $search_table_list .= "$search_table $search_group_name, ";
        push @rank_list,$rank;
        $fts_list .= " AND $fts_where AND b.id = $search_group_name.source";

        if ($metabib_field) {
            $fts_list .= " AND $curr_search_group.field = " . $metabib_field->id;
            $metabib_field = undef;
        }

        if ($prev_search_group) {
            $join_table_list .= " AND $prev_search_group.source = $curr_search_group.source";
        }
    }

    my $metabib_record_descriptor = metabib::record_descriptor->table;
    my $metabib_full_rec = metabib::full_rec->table;
    my $metabib_metarecord = metabib::metarecord->table;
    my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
    my $asset_call_number_table = asset::call_number->table;
    my $asset_copy_table = asset::copy->table;
    my $cs_table = config::copy_status->table;
    my $cl_table = asset::copy_location->table;
    my $br_table = biblio::record_entry->table;
    my $source_table = config::bib_source->table;


    my $bonuses = join (' * ', @bonus_lists);
    my $relevance = join (' + ', @rank_list);
    $relevance = "AVG( ($relevance) * ($bonuses) )";

    my $string_default_sort = 'zzzz';
    $string_default_sort = 'AAAA' if ($sort_dir eq 'DESC');

    my $number_default_sort = '9999';
    $number_default_sort = '0000' if ($sort_dir eq 'DESC');

    my $rank = $relevance;
    if (lc($sort) eq 'pubdate') {
        $rank = <<"        RANK";
            ( FIRST ((
                SELECT  COALESCE(SUBSTRING(frp.value FROM E'\\\\d{4}'),'$number_default_sort')::INT
                  FROM  $metabib_full_rec frp
                  WHERE frp.record = b.id
                    AND frp.tag = '260'
                    AND frp.subfield = 'c'
                  LIMIT 1
            )) )
        RANK
    } elsif (lc($sort) eq 'create_date') {
        $rank = <<"        RANK";
            ( FIRST (( SELECT create_date FROM $br_table rbr WHERE rbr.id = b.id)) )
        RANK
    } elsif (lc($sort) eq 'edit_date') {
        $rank = <<"        RANK";
            ( FIRST (( SELECT edit_date FROM $br_table rbr WHERE rbr.id = b.id)) )
        RANK
    } elsif (lc($sort) eq 'title') {
        $rank = <<"        RANK";
            ( FIRST ((
                SELECT  COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'$string_default_sort')
                  FROM  $metabib_full_rec frt
                  WHERE frt.record = b.id
                    AND frt.tag = '245'
                    AND frt.subfield = 'a'
                  LIMIT 1
            )) )
        RANK
    } elsif (lc($sort) eq 'author') {
        $rank = <<"        RANK";
            ( FIRST((
                SELECT  COALESCE(LTRIM(fra.value),'$string_default_sort')
                  FROM  $metabib_full_rec fra
                  WHERE fra.record = b.id
                    AND fra.tag LIKE '1%'
                    AND fra.subfield = 'a'
                  ORDER BY fra.tag::text::int
                  LIMIT 1
            )) )
        RANK
    } else {
        push @bonus_values, @bonus_values;
        $sort = undef;
    }


    my $select = <<"    SQL";
        SELECT  b.id,
            $relevance AS rel,
            $rank AS rank,
            b.source
        FROM    $search_table_list
            $metabib_record_descriptor rd,
            $source_table src,
            $br_table b
        WHERE   rd.record = b.id
            AND b.active IS TRUE
            AND b.deleted IS FALSE
            $fts_list
            $join_table_list
            $t_filter
            $f_filter
            $v_filter
            $a_filter
            $l_filter
            $lf_filter
        GROUP BY b.id, b.source
        ORDER BY 3 $sort_dir
        LIMIT $visibility_limit
    SQL

    if ($self->api_name !~ /staff/o) {
        $select = <<"        SQL";

            SELECT  s.*
              FROM  ($select) s
                LEFT OUTER JOIN $source_table src ON (s.source = src.id)
              WHERE EXISTS (
                SELECT  1
                  FROM  $asset_call_number_table cn,
                    $asset_copy_table cp,
                    $cs_table cs,
                    $cl_table cl,
                    $descendants d
                  WHERE cn.record = s.id
                    AND cp.status = cs.id
                    AND cp.location = cl.id
                    AND cp.call_number = cn.id
                    AND cp.opac_visible IS TRUE
                    AND cs.opac_visible IS TRUE
                    AND cl.opac_visible IS TRUE
                    AND d.opac_visible IS TRUE
                    AND cp.deleted IS FALSE
                    AND cn.deleted IS FALSE
                    AND cp.circ_lib = d.id
                    $avail_filter
                  LIMIT 1
                )
                OR src.transcendant IS TRUE
              ORDER BY 3 $sort_dir
        SQL
    } else {
        $select = <<"        SQL";

            SELECT  s.*
              FROM  ($select) s
                LEFT OUTER JOIN $source_table src ON (s.source = src.id)
              WHERE EXISTS (
                SELECT  1
                  FROM  $asset_call_number_table cn,
                    $asset_copy_table cp,
                    $descendants d
                  WHERE cn.record = s.id
                    AND cp.call_number = cn.id
                    AND cn.deleted IS FALSE
                    AND cp.circ_lib = d.id
                    AND cp.deleted IS FALSE
                    $avail_filter
                  LIMIT 1
                )
                OR NOT EXISTS (
                SELECT  1
                  FROM  $asset_call_number_table cn
                  WHERE cn.record = s.id
                  LIMIT 1
                )
                OR src.transcendant IS TRUE
              ORDER BY 3 $sort_dir
        SQL
    }


    $log->debug("Field Search SQL :: [$select]",DEBUG);

    my $recs = $_cdbi->{title}->db_Main->selectall_arrayref(
            $select, {},
            @bonus_values, @types, @forms, @vformats, @aud, @lang, @lit_form
    );
    
    $log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

    my $count = scalar(@$recs);
    for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
        next unless ($$rec[0]);
        my ($mrid,$rank) = @$rec;
        $client->respond( [$mrid, sprintf('%0.3f',$rank), $count] );
    }
    return undef;
}

__PACKAGE__->register_method(
    api_name    => "open-ils.storage.biblio.multiclass.search_fts.record",
    no_tz_force => 1,
    method      => 'biblio_search_multi_class_fts',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.biblio.multiclass.search_fts.record.staff",
    no_tz_force => 1,
    method      => 'biblio_search_multi_class_fts',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.biblio.multiclass.search_fts",
    no_tz_force => 1,
    method      => 'biblio_search_multi_class_fts',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.biblio.multiclass.search_fts.staff",
    no_tz_force => 1,
    method      => 'biblio_search_multi_class_fts',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);


my %locale_map;
my $default_preferred_language;
my $default_preferred_language_weight;

# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub staged_fts {
    my $self   = shift;
    my $client = shift;
    my %args   = @_;

    if (!$locale_map{COMPLETE}) {

        my @locales = config::i18n_locale->search_where({ code => { '<>' => '' } });
        for my $locale ( @locales ) {
            $locale_map{lc($locale->code)} = $locale->marc_code;
        }
        $locale_map{COMPLETE} = 1;

    }

    my $config = OpenSRF::Utils::SettingsClient->new();

    if (!$default_preferred_language) {

        $default_preferred_language = $config->config_value(
                apps => 'open-ils.search' => app_settings => 'default_preferred_language'
        ) || $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language'
        );

    }

    if (!$default_preferred_language_weight) {

        $default_preferred_language_weight = $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language_weight'
        ) || $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language_weight'
        );
    }

    # inclusion, exclusion, delete_adjusted_inclusion, delete_adjusted_exclusion
    my $estimation_strategy = $args{estimation_strategy} || 'inclusion';

    my $ou     = $args{org_unit};
    my $limit  = $args{limit}  || 10;
    my $offset = $args{offset} ||  0;

    if (!$ou) {
        $ou = actor::org_unit->search( { parent_ou => undef } )->next->id;
    }

    if (! scalar( keys %{$args{searches}} )) {
        die "No search arguments were passed to ".$self->api_name;
    }

    my (@between,@statuses,@locations,@types,@forms,@lang,@aud,@lit_form,@vformats,@bib_level);

    if (!defined($args{preferred_language})) {
        my $ses_locale = $client->session ? $client->session->session_locale : $default_preferred_language;
        $args{preferred_language} =
            $locale_map{ lc($ses_locale) } || 'eng';
    }

    if (!defined($args{preferred_language_weight})) {
        $args{preferred_language_weight} = $default_preferred_language_weight || 2;
    }

    if ($args{available}) {
        @statuses = (0,7,12);
    }

    if (my $s = $args{locations}) {
        $s = [$s] if (!ref($s));
        @locations = @$s;
    }

    if (my $b = $args{between}) {
        if (ref($b) && @$b == 2) {
            @between = @$b;
        }
    }

    if (my $s = $args{statuses}) {
        $s = [$s] if (!ref($s));
        @statuses = @$s;
    }

    if (my $a = $args{audience}) {
        $a = [$a] if (!ref($a));
        @aud = @$a;
    }

    if (my $l = $args{language}) {
        $l = [$l] if (!ref($l));
        @lang = @$l;
    }

    if (my $f = $args{lit_form}) {
        $f = [$f] if (!ref($f));
        @lit_form = @$f;
    }

    if (my $f = $args{item_form}) {
        $f = [$f] if (!ref($f));
        @forms = @$f;
    }

    if (my $t = $args{item_type}) {
        $t = [$t] if (!ref($t));
        @types = @$t;
    }

    if (my $b = $args{bib_level}) {
        $b = [$b] if (!ref($b));
        @bib_level = @$b;
    }

    if (my $v = $args{vr_format}) {
        $v = [$v] if (!ref($v));
        @vformats = @$v;
    }

    # XXX legacy format and item type support
    if ($args{format}) {
        my ($t, $f) = split '-', $args{format};
        @types = split '', $t;
        @forms = split '', $f;
    }

    my %stored_proc_search_args;
    for my $search_group (sort keys %{$args{searches}}) {
        (my $search_group_name = $search_group) =~ s/\|/_/gso;
        my ($search_class,$search_field) = split /\|/, $search_group;
        $log->debug("Searching class [$search_class] and field [$search_field]",DEBUG);

        if ($search_field) {
            unless ( config::metabib_field->search( field_class => $search_class, name => $search_field )->next ) {
                $log->warn("Requested class [$search_class] or field [$search_field] does not exist!");
                return undef;
            }
        }

        my $class = $_cdbi->{$search_class};
        my $search_table = $class->table;

        my ($index_col) = $class->columns('FTS');
        $index_col ||= 'value';

        
        my $fts = OpenILS::Application::Storage::FTS->compile(
            $search_class => $args{searches}{$search_group}{term},
            $search_group_name.'.value',
            "$search_group_name.$index_col"
        );
        $fts->sql_where_clause; # this builds the ranks for us

        my @fts_ranks   = $fts->fts_rank;
        my @fts_queries = $fts->fts_query;
        my @phrases = map { lc($_) } $fts->phrases;
        my @words   = map { lc($_) } $fts->words;

        $stored_proc_search_args{$search_group} = {
            fts_rank    => \@fts_ranks,
            fts_query   => \@fts_queries,
            phrase      => \@phrases,
            word        => \@words,
        };

    }

    my $param_search_ou = $ou;
    my $param_depth = $args{depth}; $param_depth = 'NULL' unless (defined($param_depth) and length($param_depth) > 0 );
    my $param_searches = OpenSRF::Utils::JSON->perl2JSON( \%stored_proc_search_args ); $param_searches =~ s/\$//go; $param_searches = '$$'.$param_searches.'$$';
    my $param_statuses  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @statuses ) . '}$$';
    my $param_locations = '$${' . join(',', map { s/\$//go; "\"$_\"" } @locations) . '}$$';
    my $param_audience  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @aud      ) . '}$$';
    my $param_language  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @lang     ) . '}$$';
    my $param_lit_form  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @lit_form ) . '}$$';
    my $param_types     = '$${' . join(',', map { s/\$//go; "\"$_\"" } @types    ) . '}$$';
    my $param_forms     = '$${' . join(',', map { s/\$//go; "\"$_\"" } @forms    ) . '}$$';
    my $param_vformats  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @vformats ) . '}$$';
    my $param_bib_level = '$${' . join(',', map { s/\$//go; "\"$_\"" } @bib_level) . '}$$';
    my $param_before = $args{before}; $param_before = 'NULL' unless (defined($param_before) and length($param_before) > 0 );
    my $param_after  = $args{after} ; $param_after  = 'NULL' unless (defined($param_after ) and length($param_after ) > 0 );
    my $param_during = $args{during}; $param_during = 'NULL' unless (defined($param_during) and length($param_during) > 0 );
    my $param_between = '$${"' . join('","', map { int($_) } @between) . '"}$$';
    my $param_pref_lang = $args{preferred_language}; $param_pref_lang =~ s/\$//go; $param_pref_lang = '$$'.$param_pref_lang.'$$';
    my $param_pref_lang_multiplier = $args{preferred_language_weight}; $param_pref_lang_multiplier ||= 'NULL';
    my $param_sort = $args{'sort'}; $param_sort =~ s/\$//go; $param_sort = '$$'.$param_sort.'$$';
    my $param_sort_desc = defined($args{sort_dir}) && $args{sort_dir} =~ /^d/io ? "'t'" : "'f'";
    my $metarecord = $self->api_name =~ /metabib/o ? "'t'" : "'f'";
    my $staff = $self->api_name =~ /staff/o ? "'t'" : "'f'";
    my $param_rel_limit = $args{core_limit};  $param_rel_limit ||= 'NULL';
    my $param_chk_limit = $args{check_limit}; $param_chk_limit ||= 'NULL';
    my $param_skip_chk  = $args{skip_check};  $param_skip_chk  ||= 'NULL';

    my $sth = metabib::metarecord_source_map->db_Main->prepare(<<"    SQL");
        SELECT  *
          FROM  search.staged_fts(
                    $param_search_ou\:\:INT,
                    $param_depth\:\:INT,
                    $param_searches\:\:TEXT,
                    $param_statuses\:\:INT[],
                    $param_locations\:\:INT[],
                    $param_audience\:\:TEXT[],
                    $param_language\:\:TEXT[],
                    $param_lit_form\:\:TEXT[],
                    $param_types\:\:TEXT[],
                    $param_forms\:\:TEXT[],
                    $param_vformats\:\:TEXT[],
                    $param_bib_level\:\:TEXT[],
                    $param_before\:\:TEXT,
                    $param_after\:\:TEXT,
                    $param_during\:\:TEXT,
                    $param_between\:\:TEXT[],
                    $param_pref_lang\:\:TEXT,
                    $param_pref_lang_multiplier\:\:REAL,
                    $param_sort\:\:TEXT,
                    $param_sort_desc\:\:BOOL,
                    $metarecord\:\:BOOL,
                    $staff\:\:BOOL,
                    $param_rel_limit\:\:INT,
                    $param_chk_limit\:\:INT,
                    $param_skip_chk\:\:INT
                );
    SQL

    $sth->execute;

    my $recs = $sth->fetchall_arrayref({});
    my $summary_row = pop @$recs;

    my $total    = $$summary_row{total};
    my $checked  = $$summary_row{checked};
    my $visible  = $$summary_row{visible};
    my $deleted  = $$summary_row{deleted};
    my $excluded = $$summary_row{excluded};

    my $estimate = $visible;
    if ( $total > $checked && $checked ) {

        $$summary_row{hit_estimate} = FTS_paging_estimate($self, $client, $checked, $visible, $excluded, $deleted, $total);
        $estimate = $$summary_row{estimated_hit_count} = $$summary_row{hit_estimate}{$estimation_strategy};

    }

    delete $$summary_row{id};
    delete $$summary_row{rel};
    delete $$summary_row{record};

    $client->respond( $summary_row );

    $log->debug("Search yielded ".scalar(@$recs)." checked, visible results with an approximate visible total of $estimate.",DEBUG);

    for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
        delete $$rec{checked};
        delete $$rec{visible};
        delete $$rec{excluded};
        delete $$rec{deleted};
        delete $$rec{total};
        $$rec{rel} = sprintf('%0.3f',$$rec{rel});

        $client->respond( $rec );
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.biblio.multiclass.staged.search_fts",
    no_tz_force => 1,
    method      => 'staged_fts',
    api_level   => 0,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.biblio.multiclass.staged.search_fts.staff",
    no_tz_force => 1,
    method      => 'staged_fts',
    api_level   => 0,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.metabib.multiclass.staged.search_fts",
    no_tz_force => 1,
    method      => 'staged_fts',
    api_level   => 0,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.metabib.multiclass.staged.search_fts.staff",
    no_tz_force => 1,
    method      => 'staged_fts',
    api_level   => 0,
    stream      => 1,
    cachable    => 1,
);

sub FTS_paging_estimate {
    my $self   = shift;
    my $client = shift;

    my $checked  = shift;
    my $visible  = shift;
    my $excluded = shift;
    my $deleted  = shift;
    my $total    = shift;

    my $deleted_ratio = $deleted / $checked;
    my $delete_adjusted_total = $total - ( $total * $deleted_ratio );

    my $exclusion_ratio = $excluded / $checked;
    my $delete_adjusted_exclusion_ratio = $checked - $deleted ? $excluded / ($checked - $deleted) : 1;

    my $inclusion_ratio = $visible / $checked;
    my $delete_adjusted_inclusion_ratio = $checked - $deleted ? $visible / ($checked - $deleted) : 0;

    return {
        exclusion                   => int($delete_adjusted_total - ( $delete_adjusted_total * $exclusion_ratio )),
        inclusion                   => int($delete_adjusted_total * $inclusion_ratio),
        delete_adjusted_exclusion   => int($delete_adjusted_total - ( $delete_adjusted_total * $delete_adjusted_exclusion_ratio )),
        delete_adjusted_inclusion   => int($delete_adjusted_total * $delete_adjusted_inclusion_ratio)
    };
}
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.fts_paging_estimate",
    no_tz_force => 1,
    method      => 'FTS_paging_estimate',
    argc        => 5,
    strict      => 1,
    api_level   => 1,
    signature   => {
        'return'=> q#
            Hash of estimation values based on four variant estimation strategies:
                exclusion -- Estimate based on the ratio of excluded records on the current superpage;
                inclusion -- Estimate based on the ratio of visible records on the current superpage;
                delete_adjusted_exclusion -- Same as exclusion strategy, but the ratio is adjusted by deleted count;
                delete_adjusted_inclusion -- Same as inclusion strategy, but the ratio is adjusted by deleted count;
        #,
        desc    => q#
            Helper method used to determin the approximate number of
            hits for a search that spans multiple superpages.  For
            sparse superpages, the inclusion estimate will likely be the
            best estimate.  The exclusion strategy is the original, but
            inclusion is the default.
        #,
        params  => [
            {   name    => 'checked',
                desc    => 'Number of records check -- nominally the size of a superpage, or a remaining amount from the last superpage.',
                type    => 'number'
            },
            {   name    => 'visible',
                desc    => 'Number of records visible to the search location on the current superpage.',
                type    => 'number'
            },
            {   name    => 'excluded',
                desc    => 'Number of records excluded from the search location on the current superpage.',
                type    => 'number'
            },
            {   name    => 'deleted',
                desc    => 'Number of deleted records on the current superpage.',
                type    => 'number'
            },
            {   name    => 'total',
                desc    => 'Total number of records up to check_limit (superpage_size * max_superpages).',
                type    => 'number'
            }
        ]
    }
);


sub xref_count {
    my $self   = shift;
    my $client = shift;
    my $args   = shift;

    my $term  = $$args{term};
    my $limit = $$args{max} || 1;
    my $min   = $$args{min} || 1;
    my @classes = @{$$args{class}};

    $limit = $min if ($min > $limit);

    if (!@classes) {
        @classes = ( qw/ title author subject series keyword / );
    }

    my %matches;
    my $bre_table = biblio::record_entry->table;
    my $cn_table  = asset::call_number->table;
    my $cp_table  = asset::copy->table;

    for my $search_class ( @classes ) {

        my $class = $_cdbi->{$search_class};
        my $search_table = $class->table;

        my ($index_col) = $class->columns('FTS');
        $index_col ||= 'value';

        
        my $where = OpenILS::Application::Storage::FTS
            ->compile($search_class => $term, $search_class.'.value', "$search_class.$index_col")
            ->sql_where_clause;

        my $SQL = <<"        SQL";
            SELECT  COUNT(DISTINCT X.source)
              FROM  (SELECT $search_class.source
                  FROM  $search_table $search_class
                    JOIN $bre_table b ON (b.id = $search_class.source)
                  WHERE $where
                    AND NOT b.deleted
                    AND b.active
                  LIMIT $limit) X
              HAVING COUNT(DISTINCT X.source) >= $min;
        SQL

        my $res = $class->db_Main->selectrow_arrayref( $SQL );
        $matches{$search_class} = $res ? $res->[0] : 0;
    }

    return \%matches;
}
__PACKAGE__->register_method(
    api_name  => "open-ils.storage.search.xref",
    no_tz_force => 1,
    method    => 'xref_count',
    api_level => 1,
);

# Takes an abstract query object and recursively turns it back into a string
# for QueryParser.
sub abstract_query2str {
    my ($self, $conn, $query) = @_;

    return QueryParser::Canonicalize::abstract_query2str_impl($query, 0, $OpenILS::Application::Storage::QParser);
}

__PACKAGE__->register_method(
    api_name    => "open-ils.storage.query_parser.abstract_query.canonicalize",
    no_tz_force => 1,
    method      => "abstract_query2str",
    api_level   => 1,
    signature   => {
        params  => [
            {desc => q/
Abstract query parser object, with complete config data. For example input,
see the 'abstract_query' part of the output of an API call like
open-ils.search.biblio.multiclass.query, when called with the return_abstract
flag set to true./,
                type => "object"}
        ],
        return => { type => "string", desc => "String representation of abstract query object" }
    }
);

sub str2abstract_query {
    my ($self, $conn, $query, $qp_opts, $with_config) = @_;

    my %use_opts = ( # reasonable defaults? should these even be hardcoded here?
        superpage => 1,
        superpage_size => 1000,
        core_limit => 25000,
        query => $query,
        (ref $opts eq 'HASH' ? %$opts : ())
    );

    $with_config ||= 0;

    # grab the query parser and initialize it
    my $parser = $OpenILS::Application::Storage::QParser;
    $parser->use;

    _initialize_parser($parser) unless $parser->initialization_complete;

    my $query = $parser->new(%use_opts)->parse;

    return $query->parse_tree->to_abstract_query(with_config => $with_config);
}

__PACKAGE__->register_method(
    api_name    => "open-ils.storage.query_parser.abstract_query.from_string",
    no_tz_force => 1,
    method      => "str2abstract_query",
    api_level   => 1,
    signature   => {
        params  => [
            {desc => "Query", type => "string"},
            {desc => q/Arguments for initializing QueryParser (optional)/,
                type => "object"},
            {desc => q/Flag enabling inclusion of QP config in returned object (optional, default false)/,
                type => "bool"}
        ],
        return => { type => "object", desc => "abstract representation of query parser query" }
    }
);

my @available_statuses_cache;
sub available_statuses {
    if (!scalar(@available_statuses_cache)) {
       @available_statuses_cache = map { $_->id } config::copy_status->search_where({is_available => 't'});
    }
    return @available_statuses_cache;
}

sub query_parser_fts {
    my $self = shift;
    my $client = shift;
    my %args = @_;


    # grab the query parser and initialize it
    my $parser = $OpenILS::Application::Storage::QParser;
    $parser->use;

    _initialize_parser($parser) unless $parser->initialization_complete;

    # populate the locale/language map
    if (!$locale_map{COMPLETE}) {

        my @locales = config::i18n_locale->search_where({ code => { '<>' => '' } });
        for my $locale ( @locales ) {
            $locale_map{lc($locale->code)} = $locale->marc_code;
        }
        $locale_map{COMPLETE} = 1;

    }

    # I hope we have a query!
    if (! $args{query} ) {
        die "No query was passed to ".$self->api_name;
    }

    my $default_CD_modifiers = OpenSRF::Utils::SettingsClient->new->config_value(
        apps => 'open-ils.search' => app_settings => 'default_CD_modifiers'
    );

    # Protect against empty / missing default_CD_modifiers setting
    if ($default_CD_modifiers and !ref($default_CD_modifiers)) {
        $args{query} = "$default_CD_modifiers $args{query}";
    }

    my $simple_plan = $args{_simple_plan};
    # remove bad chunks of the %args hash
    for my $bad ( grep { /^_/ } keys(%args)) {
        delete($args{$bad});
    }


    # parse the query and supply any query-level %arg-based defaults
    # we expect, and make use of, query, superpage, superpage_size, debug and core_limit args
    my $query = $parser->new( %args )->parse;

    my $config = OpenSRF::Utils::SettingsClient->new();

    # set the locale-based default preferred location
    if (!$query->parse_tree->find_filter('preferred_language')) {
        $parser->default_preferred_language( $args{preferred_language} );

        if (!$parser->default_preferred_language) {
            my $ses_locale = $client->session ? $client->session->session_locale : '';
            $parser->default_preferred_language( $locale_map{ lc($ses_locale) } );
        }

        if (!$parser->default_preferred_language) { # still nothing...
            my $tmp_dpl = $config->config_value(
                apps => 'open-ils.search' => app_settings => 'default_preferred_language'
            ) || $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language'
            );

            $parser->default_preferred_language( $tmp_dpl )
        }
    }


    # set the global default language multiplier
    if (!$query->parse_tree->find_filter('preferred_language_weight') and !$query->parse_tree->find_filter('preferred_language_multiplier')) {
        my $tmp_dplw;

        if ($tmp_dplw = $args{preferred_language_weight} || $args{preferred_language_multiplier} ) {
            $parser->default_preferred_language_multiplier($tmp_dplw);

        } else {
            $tmp_dplw = $config->config_value(
                apps => 'open-ils.search' => app_settings => 'default_preferred_language_weight'
            ) || $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language_weight'
            );

            $parser->default_preferred_language_multiplier( $tmp_dplw );
        }
    }

    # gather the site, if one is specified, defaulting to the in-query version
    my $ou = $args{org_unit};
    if (my ($filter) = $query->parse_tree->find_filter('site')) {
            $ou = $filter->args->[0] if (@{$filter->args});
    }
    $ou = actor::org_unit->search( { shortname => $ou } )->next->id if ($ou and $ou !~ /^(-)?\d+$/);


#    # XXX The following, along with most of the surrounding code, is actually dead now. However, realigning to be more "true" and match surrounding.
#    # gather lasso, as with $ou
    my $lasso = $args{lasso};
#    if (my ($filter) = $query->parse_tree->find_filter('lasso')) {
#            $lasso = $filter->args->[0] if (@{$filter->args});
#    }
#    # search by name if an id (number) wasn't given
#    $lasso = actor::org_lasso->search( { name => $lasso } )->next->id if ($lasso and $lasso !~ /^\d+$/);
#
#    # gather lasso org list
#    my $lasso_orgs = [];
#    $lasso_orgs = [actor::org_lasso_map->search( { lasso => $lasso } )] if ($lasso);
#
#
##    # XXX once we have org_unit containers, we can make user-defined lassos .. WHEEE
##    # gather user lasso, as with $ou and lasso
    my $mylasso = $args{my_lasso};
##    if (my ($filter) = $query->parse_tree->find_filter('my_lasso')) {
##            $mylasso = $filter->args->[0] if (@{$filter->args});
##    }
##    $mylasso = actor::org_unit->search( { name => $mylasso } )->next->id if ($mylasso and $mylasso !~ /^\d+$/);
#
#
#    # if we have a lasso, go with that, otherwise ... ou
#    $ou = $lasso if ($lasso);

    # gather the preferred OU, if one is specified, as with $ou
    my $pref_ou = $args{pref_ou};
    if (my ($filter) = $query->parse_tree->find_filter('pref_ou')) {
            $pref_ou = $filter->args->[0] if (@{$filter->args});
    }
    $pref_ou = actor::org_unit->search( { shortname => $pref_ou } )->next->id if ($pref_ou and $pref_ou !~ /^(-)?\d+$/);

    # get the default $ou if we have nothing
    $ou = actor::org_unit->search( { parent_ou => undef } )->next->id if (!$ou and !$lasso and !$mylasso);


    # XXX when user lassos are here, check to make sure we don't have one -- it'll be passed in the depth, with an ou of 0
    # gather the depth, if one is specified, defaulting to the in-query version
    my $depth = $args{depth};
    if (my ($filter) = $query->parse_tree->find_filter('depth')) {
            $depth = $filter->args->[0] if (@{$filter->args});
    }
    $depth = actor::org_unit->search_where( [{ name => $depth },{ opac_label => $depth }], {limit => 1} )->next->id if ($depth and $depth !~ /^\d+$/);


    # gather the limit or default to 10
    my $limit = $args{check_limit};
    if (my ($filter) = $query->parse_tree->find_filter('limit')) {
            $limit = $filter->args->[0] if (@{$filter->args});
    }
    if (my ($filter) = $query->parse_tree->find_filter('check_limit')) {
            $limit = $filter->args->[0] if (@{$filter->args});
    }


    # gather the offset or default to 0
    my $offset = $args{skip_check} || $args{offset};
    if (my ($filter) = $query->parse_tree->find_filter('offset')) {
            $offset = $filter->args->[0] if (@{$filter->args});
    }
    if (my ($filter) = $query->parse_tree->find_filter('skip_check')) {
            $offset = $filter->args->[0] if (@{$filter->args});
    }


    # gather the estimation strategy or default to inclusion
    my $estimation_strategy = $args{estimation_strategy} || 'inclusion';
    if (my ($filter) = $query->parse_tree->find_filter('estimation_strategy')) {
            $estimation_strategy = $filter->args->[0] if (@{$filter->args});
    }


    # gather the estimation strategy or default to inclusion
    my $core_limit = $args{core_limit};
    if (my ($filter) = $query->parse_tree->find_filter('core_limit')) {
            $core_limit = $filter->args->[0] if (@{$filter->args});
    }


    # gather statuses, and then forget those if we have an #available modifier
    my @statuses;
    if ($query->parse_tree->find_modifier('available')) {
        @statuses = available_statuses();
    } elsif (my ($filter) = $query->parse_tree->find_filter('statuses')) {
        @statuses = @{$filter->args} if (@{$filter->args});
    }


    # gather locations
    my @location;
    if (my ($filter) = $query->parse_tree->find_filter('locations')) {
        @location = @{$filter->args} if (@{$filter->args});
    }

    # gather location_groups
    if (my ($filter) = $query->parse_tree->find_filter('location_groups')) {
        my @loc_groups = ();
        @loc_groups = @{$filter->args} if (@{$filter->args});
        
        # collect the mapped locations and add them to the locations() filter
        if (@loc_groups) {

            my $cstore = OpenSRF::AppSession->create( 'open-ils.cstore' );
            my $maps = $cstore->request(
                'open-ils.cstore.direct.asset.copy_location_group_map.search.atomic',
                {lgroup => \@loc_groups})->gather(1);

            push(@location, $_->location) for @$maps;
        }
    }


    my $param_check = $limit || $query->superpage_size || 'NULL';
    my $param_offset = $offset || 'NULL';
    my $param_limit = $core_limit || 'NULL';

    my $sp = $query->superpage || 1;
    if ($sp > 1) {
        $param_offset = ($sp - 1) * $sp_size;
    }

    my $param_search_ou = $ou;
    my $param_depth = $depth; $param_depth = 'NULL' unless (defined($depth) and length($depth) > 0 );
    my $param_core_query = $query->parse_tree->toSQL;
    my $param_statuses = '$${' . join(',', map { s/\$//go; "\"$_\""} @statuses) . '}$$';
    my $param_locations = '$${' . join(',', map { s/\$//go; "\"$_\""} @location) . '}$$';
    my $staff = ($self->api_name =~ /staff/ or $query->parse_tree->find_modifier('staff')) ? "'t'" : "'f'";
    my $deleted_search = ($query->parse_tree->find_modifier('deleted')) ? "'t'" : "'f'";
    my $metarecord = ($self->api_name =~ /metabib/ or $query->parse_tree->find_modifier('metabib') or $query->parse_tree->find_modifier('metarecord')) ? "'t'" : "'f'";
    my $param_pref_ou = $pref_ou || 'NULL';

    my $sth = metabib::metarecord_source_map->db_Main->prepare(<<"    SQL");
        -- bib search: $args{query}
        $param_core_query
    SQL

    $sth->execute;

    my $recs = $sth->fetchall_arrayref({});
    my $summary_row = pop @$recs;

    my $total    = $$summary_row{total};
    my $checked  = $$summary_row{checked};
    my $visible  = $$summary_row{visible};
    my $deleted  = $$summary_row{deleted};
    my $excluded = $$summary_row{excluded};

    delete $$summary_row{id};
    delete $$summary_row{rel};
    delete $$summary_row{record};
    delete $$summary_row{badges};
    delete $$summary_row{popularity};

    if (defined($simple_plan)) {
        $$summary_row{complex_query} = $simple_plan ? 0 : 1;
    } else {
        $$summary_row{complex_query} = $query->simple_plan ? 0 : 1;
    }

    if ($args{return_query}) {
        $$summary_row{query_struct} = $query->parse_tree->to_abstract_query();
        $$summary_row{canonicalized_query} = QueryParser::Canonicalize::abstract_query2str_impl($$summary_row{query_struct}, 0, $parser);
    }

    $client->respond( $summary_row );

    $log->debug("Search yielded ".scalar(@$recs)." checked, visible results with an approximate visible total of $visible.",DEBUG);

    for my $rec (@$recs) {
        delete $$rec{checked};
        delete $$rec{visible};
        delete $$rec{excluded};
        delete $$rec{deleted};
        delete $$rec{total};
        $$rec{rel} = sprintf('%0.3f',$$rec{rel});

        $client->respond( $rec );
    }
    return undef;
}
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.query_parser_search",
    no_tz_force => 1,
    method      => 'query_parser_fts',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);

my $top_org;

sub query_parser_fts_wrapper {
    my $self = shift;
    my $client = shift;
    my %args = @_;

    $log->debug("Entering compatability wrapper function for old-style staged search", DEBUG);
    # grab the query parser and initialize it
    my $parser = $OpenILS::Application::Storage::QParser;
    $parser->use;

    _initialize_parser($parser) unless $parser->initialization_complete;

    $args{searches} ||= {};
    if (!scalar(keys(%{$args{searches}})) && !$args{query}) {
        die "No search arguments were passed to ".$self->api_name;
    }

    $top_org ||= actor::org_unit->search( { parent_ou => undef } )->next;

    my $base_query = $args{query} || '';
    if (scalar(keys(%{$args{searches}}))) {
        $log->debug("Constructing QueryParser query from staged search hash ...", DEBUG);
        for my $sclass ( keys %{$args{searches}} ) {
            $log->debug(" --> staged search key: $sclass --> term: $args{searches}{$sclass}{term}", DEBUG);
            $base_query .= " $sclass: $args{searches}{$sclass}{term}";
        }
    }

    my $query = $base_query;
    $log->debug("Full base query: $base_query", DEBUG);

    $query = "$args{facets} $query" if  ($args{facets});

    if (!$locale_map{COMPLETE}) {

        my @locales = config::i18n_locale->search_where({ code => { '<>' => '' } });
        for my $locale ( @locales ) {
            $locale_map{lc($locale->code)} = $locale->marc_code;
        }
        $locale_map{COMPLETE} = 1;

    }

    my $base_plan = $parser->new( query => $base_query )->parse;

    $query = "preferred_language($args{preferred_language}) $query"
        if ($args{preferred_language} and !$base_plan->parse_tree->find_filter('preferred_language'));
    $query = "preferred_language_weight($args{preferred_language_weight}) $query"
        if ($args{preferred_language_weight} and !$base_plan->parse_tree->find_filter('preferred_language_weight') and !$base_plan->parse_tree->find_filter('preferred_language_multiplier'));


    my $borgs = undef;
    if (!$base_plan->parse_tree->find_filter('badge_orgs')) {
        # supply a suitable badge_orgs filter unless user has
        # explicitly supplied one
        my $site = undef;

        my @lg_id_list = (); # We must define the variable with a static value
                             # because an idomatic my+set causes the previous
                             # value is remembered via closure.  

        @lg_id_list = @{$args{location_groups}} if (ref $args{location_groups});

        my ($lg_filter) = $base_plan->parse_tree->find_filter('location_groups');
        @lg_id_list = @{$lg_filter->args} if ($lg_filter && @{$lg_filter->args});

        if (@lg_id_list) {
            my @borg_list;
            for my $lg ( grep { /^\d+$/ } @lg_id_list ) {
                my $lg_obj = asset::copy_location_group->retrieve($lg);
                next unless $lg_obj;
    
                push(@borg_list, @{$U->get_org_ancestors(''.$lg_obj->owner)});
            }
            $borgs = join(',', uniq @borg_list) if @borg_list;
        }
    
        if (!$borgs) {
            my ($site_filter) = $base_plan->parse_tree->find_filter('site');
            if ($site_filter && @{$site_filter->args}) {
                $site = $top_org if ($site_filter->args->[0] eq '-');
                $site = $top_org if ($site_filter->args->[0] eq $top_org->shortname);
                $site = actor::org_unit->search( { shortname => $site_filter->args->[0] })->next unless ($site);
            } elsif ($args{org_unit}) {
                $site = $top_org if ($args{org_unit} eq '-');
                $site = $top_org if ($args{org_unit} eq $top_org->shortname);
                $site = actor::org_unit->search( { shortname => $args{org_unit} })->next unless ($site);
            } else {
                $site = $top_org;
            }

            if ($site) {
                $borgs = $U->get_org_ancestors($site->id);
                $borgs = @$borgs ?  join(',', @$borgs) : undef;
            }
        }
    }

    # gather the limit or default to 10
    my $limit = delete($args{check_limit}) || $base_plan->superpage_size;
    if (my ($filter) = $base_plan->parse_tree->find_filter('limit')) {
            $limit = $filter->args->[0] if (@{$filter->args});
    }
    if (my ($filter) = $base_plan->parse_tree->find_filter('check_limit')) {
            $limit = $filter->args->[0] if (@{$filter->args});
    }

    # gather the offset or default to 0
    my $offset = delete($args{skip_check}) || delete($args{offset}) || 0;
    if (my ($filter) = $base_plan->parse_tree->find_filter('offset')) {
            $offset = $filter->args->[0] if (@{$filter->args});
    }
    if (my ($filter) = $base_plan->parse_tree->find_filter('skip_check')) {
            $offset = $filter->args->[0] if (@{$filter->args});
    }


    $query = "check_limit($limit) $query" if (defined $limit);
    $query = "skip_check($offset) $query" if (defined $offset);
    $query = "estimation_strategy($args{estimation_strategy}) $query" if ($args{estimation_strategy});
    $query = "badge_orgs($borgs) $query" if ($borgs);

    # XXX All of the following, down to the 'return' is basically dead code. someone higher up should handle it
    $query = "site($args{org_unit}) $query" if ($args{org_unit});
    $query = "lasso($args{lasso}) $query" if ($args{lasso});
    $query = "depth($args{depth}) $query" if (defined($args{depth}));
    $query = "sort($args{sort}) $query" if ($args{sort});
    $query = "core_limit($args{core_limit}) $query" if ($args{core_limit});
#    $query = "limit($args{limit}) $query" if ($args{limit});
#    $query = "skip_check($args{skip_check}) $query" if ($args{skip_check});
    $query = "superpage($args{superpage}) $query" if ($args{superpage});
    $query = "offset($args{offset}) $query" if ($args{offset});
    $query = "#metarecord $query" if ($self->api_name =~ /metabib/);
    $query = "from_metarecord($args{from_metarecord}) $query" if ($args{from_metarecord});
    $query = "#available $query" if ($args{available});
    $query = "#descending $query" if ($args{sort_dir} && $args{sort_dir} =~ /^d/i);
    $query = "#staff $query" if ($self->api_name =~ /staff/);
    $query = "before($args{before}) $query" if (defined($args{before}) and $args{before} =~ /^\d+$/);
    $query = "after($args{after}) $query" if (defined($args{after}) and $args{after} =~ /^\d+$/);
    $query = "during($args{during}) $query" if (defined($args{during}) and $args{during} =~ /^\d+$/);
    $query = "between($args{between}[0],$args{between}[1]) $query"
        if ( ref($args{between}) and @{$args{between}} == 2 and $args{between}[0] =~ /^\d+$/ and $args{between}[1] =~ /^\d+$/ );


    my (@between,@statuses,@locations,@location_groups,@types,@forms,@lang,@aud,@lit_form,@vformats,@bib_level);

    # XXX legacy format and item type support
    if ($args{format}) {
        my ($t, $f) = split '-', $args{format};
        $args{item_type} = [ split '', $t ];
        $args{item_form} = [ split '', $f ];
    }

    for my $filter ( qw/locations location_groups statuses audience language lit_form item_form item_type bib_level vr_format badges/ ) {
        if (my $s = $args{$filter}) {
            $s = [$s] if (!ref($s));

            my @filter_list = @$s;

            next if (@filter_list == 0);

            my $filter_string = join ',', @filter_list;
            $query = "$query $filter($filter_string)";
        }
    }

    $log->debug("Full QueryParser query: $query", DEBUG);

    return query_parser_fts($self, $client, query => $query, _simple_plan => $base_plan->simple_plan, return_query => $args{return_query} );
}
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.biblio.multiclass.staged.search_fts",
    no_tz_force => 1,
    method      => 'query_parser_fts_wrapper',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.biblio.multiclass.staged.search_fts.staff",
    no_tz_force => 1,
    method      => 'query_parser_fts_wrapper',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.metabib.multiclass.staged.search_fts",
    no_tz_force => 1,
    method      => 'query_parser_fts_wrapper',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);
__PACKAGE__->register_method(
    api_name    => "open-ils.storage.metabib.multiclass.staged.search_fts.staff",
    no_tz_force => 1,
    method      => 'query_parser_fts_wrapper',
    api_level   => 1,
    stream      => 1,
    cachable    => 1,
);


1;

