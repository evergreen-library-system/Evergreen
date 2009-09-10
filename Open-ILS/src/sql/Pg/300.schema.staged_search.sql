/*
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */


DROP SCHEMA search CASCADE;

BEGIN;

CREATE SCHEMA search;

CREATE TABLE search.relevance_adjustment (
    id          SERIAL  PRIMARY KEY,
    active      BOOL    NOT NULL DEFAULT TRUE,
    field       INT     NOT NULL REFERENCES config.metabib_field (id) DEFERRABLE INITIALLY DEFERRED,
    bump_type   TEXT    NOT NULL CHECK (bump_type IN ('word_order','first_word','full_match')),
    multiplier  NUMERIC NOT NULL DEFAULT 1.0
);
CREATE UNIQUE INDEX bump_once_per_field_idx ON search.relevance_adjustment ( field, bump_type );

CREATE OR REPLACE FUNCTION search.pick_table (TEXT) RETURNS TEXT AS $$
    SELECT  CASE
                WHEN $1 = 'author'  THEN 'metabib.author_field_entry'
                WHEN $1 = 'title'   THEN 'metabib.title_field_entry'
                WHEN $1 = 'subject' THEN 'metabib.subject_field_entry'
                WHEN $1 = 'keyword' THEN 'metabib.keyword_field_entry'
                WHEN $1 = 'series'  THEN 'metabib.series_field_entry'
            END;
$$ LANGUAGE SQL;

CREATE TYPE search.search_result AS ( id BIGINT, rel NUMERIC, record INT, total INT, checked INT, visible INT, deleted INT, excluded INT );
CREATE TYPE search.search_args AS ( id INT, field_class TEXT, field_name TEXT, table_alias TEXT, term TEXT, term_type TEXT );

CREATE OR REPLACE FUNCTION search.staged_fts (

    param_search_ou INT,
    param_depth     INT,
    param_searches  TEXT, -- JSON hash, to be turned into a resultset via search.parse_search_args
    param_statuses  INT[],
    param_locations INT[],
    param_audience  TEXT[],
    param_language  TEXT[],
    param_lit_form  TEXT[],
    param_types     TEXT[],
    param_forms     TEXT[],
    param_vformats  TEXT[],
    param_bib_level TEXT[],
    param_before    TEXT,
    param_after     TEXT,
    param_during    TEXT,
    param_between   TEXT[],
    param_pref_lang TEXT,
    param_pref_lang_multiplier REAL,
    param_sort      TEXT,
    param_sort_desc BOOL,
    metarecord      BOOL,
    staff           BOOL,
    param_rel_limit INT,
    param_chk_limit INT,
    param_skip_chk  INT
 
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    query_part          search.search_args%ROWTYPE;
    phrase_query_part   search.search_args%ROWTYPE;
    rank_adjust_id      INT;
    core_rel_limit      INT;
    core_chk_limit      INT;
    core_skip_chk       INT;
    rank_adjust         search.relevance_adjustment%ROWTYPE;
    query_table         TEXT;
    tmp_text            TEXT;
    tmp_int             INT;
    current_rank        TEXT;
    ranks               TEXT[] := '{}';
    query_table_alias   TEXT;
    from_alias_array    TEXT[] := '{}';
    used_ranks          TEXT[] := '{}';
    mb_field            INT;
    mb_field_list       INT[];
    search_org_list     INT[];
    select_clause       TEXT := 'SELECT';
    from_clause         TEXT := ' FROM  metabib.metarecord_source_map m JOIN metabib.rec_descriptor mrd ON (m.source = mrd.record) ';
    where_clause        TEXT := ' WHERE 1=1 ';
    mrd_used            BOOL := FALSE;
    sort_desc           BOOL := FALSE;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;
    vis_limit_query     TEXT;
    inner_where_clause  TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

BEGIN

    core_rel_limit := COALESCE( param_rel_limit, 25000 );
    core_chk_limit := COALESCE( param_chk_limit, 1000 );
    core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF metarecord THEN
        select_clause := select_clause || ' m.metarecord as id, array_accum(distinct m.source) as records,';
    ELSE
        select_clause := select_clause || ' m.source as id, array_accum(distinct m.source) as records,';
    END IF;

    -- first we need to construct the base query
    FOR query_part IN SELECT * FROM search.parse_search_args(param_searches) WHERE term_type = 'fts_query' LOOP

        inner_where_clause := 'index_vector @@ ' || query_part.term;

        IF query_part.field_name IS NOT NULL THEN

           SELECT  id INTO mb_field
             FROM  config.metabib_field
             WHERE field_class = query_part.field_class
                   AND name = query_part.field_name;

            IF FOUND THEN
                inner_where_clause := inner_where_clause ||
                    ' AND ' || 'field = ' || mb_field;
            END IF;

        END IF;

        -- moving on to the rank ...
        SELECT  * INTO query_part
          FROM  search.parse_search_args(param_searches)
          WHERE term_type = 'fts_rank'
                AND table_alias = query_part.table_alias;

        current_rank := query_part.term || ' * ' || query_part.table_alias || '_weight.weight';

        IF query_part.field_name IS NOT NULL THEN

           SELECT  array_accum(distinct id) INTO mb_field_list
             FROM  config.metabib_field
             WHERE field_class = query_part.field_class
                   AND name = query_part.field_name;

        ELSE

           SELECT  array_accum(distinct id) INTO mb_field_list
             FROM  config.metabib_field
             WHERE field_class = query_part.field_class;

        END IF;

        FOR rank_adjust IN SELECT * FROM search.relevance_adjustment WHERE active AND field IN ( SELECT * FROM search.explode_array( mb_field_list ) ) LOOP

            IF NOT rank_adjust.bump_type = ANY (used_ranks) THEN

                IF rank_adjust.bump_type = 'first_word' THEN
                    SELECT  term INTO tmp_text
                      FROM  search.parse_search_args(param_searches)
                      WHERE table_alias = query_part.table_alias AND term_type = 'word'
                      ORDER BY id
                      LIMIT 1;

                    tmp_text := query_part.table_alias || '.value ILIKE ' || quote_literal( tmp_text || '%' );

                ELSIF rank_adjust.bump_type = 'word_order' THEN
                    SELECT  array_to_string( array_accum( term ), '%' ) INTO tmp_text
                      FROM  search.parse_search_args(param_searches)
                      WHERE table_alias = query_part.table_alias AND term_type = 'word';

                    tmp_text := query_part.table_alias || '.value ILIKE ' || quote_literal( '%' || tmp_text || '%' );

                ELSIF rank_adjust.bump_type = 'full_match' THEN
                    SELECT  array_to_string( array_accum( term ), E'\\s+' ) INTO tmp_text
                      FROM  search.parse_search_args(param_searches)
                      WHERE table_alias = query_part.table_alias AND term_type = 'word';

                    tmp_text := query_part.table_alias || '.value  ~ ' || quote_literal( '^' || tmp_text || E'\\W*$' );

                END IF;


                IF tmp_text IS NOT NULL THEN
                    current_rank := current_rank || ' * ( CASE WHEN ' || tmp_text ||
                        ' THEN ' || rank_adjust.multiplier || '::REAL ELSE 1.0 END )';
                END IF;

                used_ranks := array_append( used_ranks, rank_adjust.bump_type );

            END IF;

        END LOOP;

        ranks := array_append( ranks, current_rank );
        used_ranks := '{}';

        FOR phrase_query_part IN
            SELECT  * 
              FROM  search.parse_search_args(param_searches)
              WHERE term_type = 'phrase'
                    AND table_alias = query_part.table_alias LOOP

            tmp_text := replace( phrase_query_part.term, '*', E'\\*' );
            tmp_text := replace( tmp_text, '?', E'\\?' );
            tmp_text := replace( tmp_text, '+', E'\\+' );
            tmp_text := replace( tmp_text, '|', E'\\|' );
            tmp_text := replace( tmp_text, '(', E'\\(' );
            tmp_text := replace( tmp_text, ')', E'\\)' );
            tmp_text := replace( tmp_text, '[', E'\\[' );
            tmp_text := replace( tmp_text, ']', E'\\]' );

            inner_where_clause := inner_where_clause || ' AND ' || 'value  ~* ' || quote_literal( E'(^|\\W+)' || regexp_replace(tmp_text, E'\\s+',E'\\\\s+','g') || E'(\\W+|\$)' );

        END LOOP;

        query_table := search.pick_table(query_part.field_class);

        from_clause := from_clause ||
            ' JOIN ( SELECT * FROM ' || query_table || ' WHERE ' || inner_where_clause ||
                    CASE WHEN core_rel_limit > 0 THEN ' LIMIT ' || core_rel_limit::TEXT ELSE '' END || ' ) AS ' || query_part.table_alias ||
                ' ON ( m.source = ' || query_part.table_alias || '.source )' ||
            ' JOIN config.metabib_field AS ' || query_part.table_alias || '_weight' ||
                ' ON ( ' || query_part.table_alias || '.field = ' || query_part.table_alias || '_weight.id  AND  ' || query_part.table_alias || '_weight.search_field)';

        from_alias_array := array_append(from_alias_array, query_part.table_alias);

    END LOOP;

    IF param_pref_lang IS NOT NULL AND param_pref_lang_multiplier IS NOT NULL THEN
        current_rank := ' CASE WHEN mrd.item_lang = ' || quote_literal( param_pref_lang ) ||
            ' THEN ' || param_pref_lang_multiplier || '::REAL ELSE 1.0 END ';

        -- ranks := array_append( ranks, current_rank );
    END IF;

    current_rank := ' AVG( ( (' || array_to_string( ranks, ') + (' ) || ') ) * ' || current_rank || ' ) ';
    select_clause := select_clause || current_rank || ' AS rel,';

    sort_desc = param_sort_desc;

    IF param_sort = 'pubdate' THEN

        tmp_text := '999999';
        IF param_sort_desc THEN tmp_text := '0'; END IF;

        current_rank := $$ COALESCE( FIRST(NULLIF(REGEXP_REPLACE(mrd.date1, E'\\D+', '9', 'g'),'')), $$ || quote_literal(tmp_text) || $$ )::INT $$;

    ELSIF param_sort = 'title' THEN

        tmp_text := 'zzzzzz';
        IF param_sort_desc THEN tmp_text := '    '; END IF;

        current_rank := $$
            ( COALESCE( FIRST ((
                SELECT  LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\d+'),'0')::INT + 1 ))
                  FROM  metabib.full_rec frt
                  WHERE frt.record = m.source
                    AND frt.tag = '245'
                    AND frt.subfield = 'a'
                  LIMIT 1
            )),$$ || quote_literal(tmp_text) || $$))
        $$;

    ELSIF param_sort = 'author' THEN

        tmp_text := 'zzzzzz';
        IF param_sort_desc THEN tmp_text := '    '; END IF;

        current_rank := $$
            ( COALESCE( FIRST ((
                SELECT  LTRIM(fra.value)
                  FROM  metabib.full_rec fra
                  WHERE fra.record = m.source
                    AND fra.tag LIKE '1%'
                    AND fra.subfield = 'a'
                  ORDER BY fra.tag::text::int
                  LIMIT 1
            )),$$ || quote_literal(tmp_text) || $$))
        $$;

    ELSIF param_sort = 'create_date' THEN
            current_rank := $$( FIRST (( SELECT create_date FROM biblio.record_entry rbr WHERE rbr.id = m.source)) )$$;
    ELSIF param_sort = 'edit_date' THEN
            current_rank := $$( FIRST (( SELECT edit_date FROM biblio.record_entry rbr WHERE rbr.id = m.source)) )$$;
    ELSE
        sort_desc := NOT COALESCE(param_sort_desc, FALSE);
    END IF;

    select_clause := select_clause || current_rank || ' AS rank, ' ||
			$$ COALESCE( FIRST(NULLIF(REGEXP_REPLACE(mrd.date1, E'\\D+', '0', 'g'),'')), '0' )::INT  AS tie_break $$;

    -- now add the other qualifiers
    IF param_audience IS NOT NULL AND array_upper(param_audience, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.audience IN ('$$ || array_to_string(param_audience, $$','$$) || $$') $$;
    END IF;

    IF param_language IS NOT NULL AND array_upper(param_language, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.item_lang IN ('$$ || array_to_string(param_language, $$','$$) || $$') $$;
    END IF;

    IF param_lit_form IS NOT NULL AND array_upper(param_lit_form, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.lit_form IN ('$$ || array_to_string(param_lit_form, $$','$$) || $$') $$;
    END IF;

    IF param_types IS NOT NULL AND array_upper(param_types, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.item_type IN ('$$ || array_to_string(param_types, $$','$$) || $$') $$;
    END IF;

    IF param_forms IS NOT NULL AND array_upper(param_forms, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.item_form IN ('$$ || array_to_string(param_forms, $$','$$) || $$') $$;
    END IF;

    IF param_vformats IS NOT NULL AND array_upper(param_vformats, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.vr_format IN ('$$ || array_to_string(param_vformats, $$','$$) || $$') $$;
    END IF;

    IF param_bib_level IS NOT NULL AND array_upper(param_bib_level, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.bib_level IN ('$$ || array_to_string(param_bib_level, $$','$$) || $$') $$;
    END IF;

    IF param_before IS NOT NULL AND param_before <> '' THEN
        where_clause = where_clause || $$ AND mrd.date1 <= $$ || quote_literal(param_before) || ' ';
    END IF;

    IF param_after IS NOT NULL AND param_after <> '' THEN
        where_clause = where_clause || $$ AND mrd.date1 >= $$ || quote_literal(param_after) || ' ';
    END IF;

    IF param_during IS NOT NULL AND param_during <> '' THEN
        where_clause = where_clause || $$ AND $$ || quote_literal(param_during) || $$ BETWEEN mrd.date1 AND mrd.date2 $$;
    END IF;

    IF param_between IS NOT NULL AND array_upper(param_between, 1) > 1 THEN
        where_clause = where_clause || $$ AND mrd.date1 BETWEEN '$$ || array_to_string(param_between, $$' AND '$$) || $$' $$;
    END IF;

    core_rel_query := select_clause || from_clause || where_clause ||
                        ' GROUP BY 1 ORDER BY 4 ' || CASE WHEN sort_desc THEN 'DESC' ELSE 'ASC' END || ', 5 DESC;';

    --RAISE NOTICE 'Base Query:  %', core_rel_query;

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;
    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;
    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    OPEN core_cursor FOR EXECUTE core_rel_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;


        IF total_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % total, % checked so far ... ', total_count, check_count;
        END IF;

        IF core_chk_limit > 0 AND total_count - core_skip_chk + 1 >= core_chk_limit THEN
            total_count := total_count + 1;
            CONTINUE;
        END IF;

        total_count := total_count + 1;

        CONTINUE WHEN param_skip_chk IS NOT NULL and total_count < param_skip_chk;

        check_count := check_count + 1;

        PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );
        IF NOT FOUND THEN
            -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
            deleted_count := deleted_count + 1;
            CONTINUE;
        END IF;

        PERFORM 1
          FROM  biblio.record_entry b
                JOIN config.bib_source s ON (b.source = s.id)
          WHERE s.transcendant
                AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );

        IF FOUND THEN
            -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        PERFORM 1
          FROM  asset.call_number cn
                JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                JOIN asset.uri uri ON (map.uri = uri.id)
          WHERE NOT cn.deleted
                AND cn.label = '##URI##'
                AND uri.active
                AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                AND cn.owning_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
          LIMIT 1;

        IF FOUND THEN
            -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.status IN ( SELECT * FROM search.explode_array( param_statuses ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all status-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.location IN ( SELECT * FROM search.explode_array( param_locations ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all copy_location-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF staff IS NULL OR NOT staff THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
                    JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                    JOIN asset.copy_location cl ON (cp.location = cl.id)
                    JOIN config.copy_status cs ON (cp.status = cs.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cs.opac_visible
                    AND cl.opac_visible
                    AND cp.opac_visible
                    AND a.opac_visible
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        ELSE

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
                    JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                    JOIN asset.copy_location cl ON (cp.location = cl.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN

                PERFORM 1
                  FROM  asset.call_number cn
                  WHERE cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                  LIMIT 1;

                IF FOUND THEN
                    -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION search.explode_array(anyarray) RETURNS SETOF anyelement AS $BODY$
    SELECT ($1)[s] FROM generate_series(1, array_upper($1, 1)) AS s;
$BODY$
LANGUAGE 'sql' IMMUTABLE;

CREATE OR REPLACE FUNCTION search.parse_search_args (TEXT) RETURNS SETOF search.search_args AS $perlcode$
    use JSON::XS;
    my $json = shift;

    my $args = decode_json( $json );

    my $id = 1;

    for my $k ( keys %$args ) {
        (my $alias = $k) =~ s/\|/_/gso;
        my ($class, $field) = split /\|/, $k;
        my $part = $args->{$k};
        for my $p ( keys %$part ) {
            my $data = $part->{$p};
            $data = [$data] if (!ref($data));
            for my $datum ( @$data ) {
                return_next(
                    {   field_class => $class,
                        field_name  => $field,
                        term        => $datum,
                        table_alias => $alias,
                        term_type   => $p,
                        id          => $id,
                    }
                );
                $id++;
            }
        }
    }

    return undef;

$perlcode$ LANGUAGE PLPERLU;


COMMIT;

