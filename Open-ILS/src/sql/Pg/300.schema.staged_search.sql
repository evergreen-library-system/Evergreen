/*
 * Copyright (C) 2007-2010  Equinox Software, Inc.
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


DROP SCHEMA IF EXISTS search CASCADE;

BEGIN;

CREATE SCHEMA search;

CREATE OR REPLACE FUNCTION evergreen.pg_statistics (tab TEXT, col TEXT) RETURNS TABLE(element TEXT, frequency INT) AS $$
BEGIN
    -- This query will die on PG < 9.2, but the function can be created. We just won't use it where we can't.
    RETURN QUERY
        SELECT  e,
                f
          FROM  (SELECT ROW_NUMBER() OVER (),
                        (f * 100)::INT AS f
                  FROM  (SELECT UNNEST(most_common_elem_freqs) AS f
                          FROM  pg_stats
                          WHERE tablename = tab
                                AND attname = col
                        )x
                ) AS f
                JOIN (SELECT ROW_NUMBER() OVER (),
                             e
                       FROM (SELECT UNNEST(most_common_elems::text::text[]) AS e
                              FROM  pg_stats
                              WHERE tablename = tab
                                    AND attname = col
                            )y
                ) AS elems USING (row_number);
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.query_int_wrapper (INT[],TEXT) RETURNS BOOL AS $$
BEGIN
    RETURN $1 @@ $2::query_int;
END;
$$ LANGUAGE PLPGSQL STABLE;

CREATE TABLE search.relevance_adjustment (
    id          SERIAL  PRIMARY KEY,
    active      BOOL    NOT NULL DEFAULT TRUE,
    field       INT     NOT NULL REFERENCES config.metabib_field (id) DEFERRABLE INITIALLY DEFERRED,
    bump_type   TEXT    NOT NULL CHECK (bump_type IN ('word_order','first_word','full_match')),
    multiplier  NUMERIC NOT NULL DEFAULT 1.0
);
CREATE UNIQUE INDEX bump_once_per_field_idx ON search.relevance_adjustment ( field, bump_type );

CREATE TYPE search.search_result AS ( id BIGINT, rel NUMERIC, record INT, total INT, checked INT, visible INT, deleted INT, excluded INT, badges TEXT, popularity NUMERIC );
CREATE TYPE search.search_args AS ( id INT, field_class TEXT, field_name TEXT, table_alias TEXT, term TEXT, term_type TEXT );

CREATE OR REPLACE FUNCTION search.query_parser_fts (

    param_search_ou INT,
    param_depth     INT,
    param_query     TEXT,
    param_statuses  INT[],
    param_locations INT[],
    param_offset    INT,
    param_check     INT,
    param_limit     INT,
    metarecord      BOOL,
    staff           BOOL,
    deleted_search  BOOL,
    param_pref_ou   INT DEFAULT NULL
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];
    luri_org_list       INT[];
    tmp_int_list        INT[];

    check_limit         INT;
    core_limit          INT;
    core_offset         INT;
    tmp_int             INT;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

    luri_as_copy        BOOL;
BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    SELECT COALESCE( enabled, FALSE ) INTO luri_as_copy FROM config.global_flag WHERE name = 'opac.located_uri.act_as_copy';

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT ARRAY_AGG(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT ARRAY_AGG(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;

        IF luri_as_copy THEN
            SELECT ARRAY_AGG(distinct id) INTO luri_org_list FROM actor.org_unit_full_path( param_search_ou );
        ELSE
            SELECT ARRAY_AGG(distinct id) INTO luri_org_list FROM actor.org_unit_ancestors( param_search_ou );
        END IF;

    ELSIF param_search_ou < 0 THEN
        SELECT ARRAY_AGG(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;

        FOR tmp_int IN SELECT * FROM UNNEST(search_org_list) LOOP

            IF luri_as_copy THEN
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_full_path( tmp_int );
            ELSE
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( tmp_int );
            END IF;

            luri_org_list := luri_org_list || tmp_int_list;
        END LOOP;

        SELECT ARRAY_AGG(DISTINCT x.id) INTO luri_org_list FROM UNNEST(luri_org_list) x(id);

    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    IF param_pref_ou IS NOT NULL THEN
            IF luri_as_copy THEN
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_full_path( param_pref_ou );
            ELSE
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( param_pref_ou );
            END IF;

        luri_org_list := luri_org_list || tmp_int_list;
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        IF NOT deleted_search THEN

            PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM unnest( core_result.records ) );
            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
                deleted_count := deleted_count + 1;
                CONTINUE;
            END IF;

            PERFORM 1
              FROM  biblio.record_entry b
                    JOIN config.bib_source s ON (b.source = s.id)
              WHERE s.transcendant
                    AND b.id IN ( SELECT * FROM unnest( core_result.records ) );

            IF FOUND THEN
                -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;
                current_res.badges = core_result.badges;
                current_res.popularity = core_result.popularity;

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
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cn.owning_lib IN ( SELECT * FROM unnest( luri_org_list ) )
              LIMIT 1;

            IF FOUND THEN
                -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;
                current_res.badges = core_result.badges;
                current_res.popularity = core_result.popularity;

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
                        AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                    -- RAISE NOTICE ' % and multi-home linked records were all status-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                        -- RAISE NOTICE ' % and multi-home linked records were all copy_location-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF staff IS NULL OR NOT staff THEN

                PERFORM 1
                  FROM  asset.opac_visible_copies
                  WHERE circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                      WHERE cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            ELSE

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        PERFORM 1
                          FROM  asset.call_number cn
                                JOIN asset.copy cp ON (cp.call_number = cn.id)
                          WHERE cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                                AND NOT cp.deleted
                          LIMIT 1;

                        IF NOT FOUND THEN
                            -- Recheck Located URI visibility in the case of no "foreign" copies
                            PERFORM 1
                              FROM  asset.call_number cn
                                    JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                                    JOIN asset.uri uri ON (map.uri = uri.id)
                              WHERE NOT cn.deleted
                                    AND cn.label = '##URI##'
                                    AND uri.active
                                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                                    AND cn.owning_lib NOT IN ( SELECT * FROM unnest( luri_org_list ) )
                              LIMIT 1;

                            IF FOUND THEN
                                -- RAISE NOTICE ' % were excluded for foreign located URIs... ', core_result.records;
                                excluded_count := excluded_count + 1;
                                CONTINUE;
                            END IF;
                        ELSE
                            -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                            excluded_count := excluded_count + 1;
                            CONTINUE;
                        END IF;
                    END IF;

                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;
        current_res.badges = core_result.badges;
        current_res.popularity = core_result.popularity;

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
    current_res.badges = NULL;
    current_res.popularity = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION search.facets_for_record_set(ignore_facet_classes text[], hits bigint[]) RETURNS TABLE(id integer, value text, count bigint)
AS $f$
    SELECT id, value, count
      FROM (
        SELECT  mfae.field AS id,
                mfae.value,
                COUNT(DISTINCT mfae.source),
                row_number() OVER (
                    PARTITION BY mfae.field ORDER BY COUNT(DISTINCT mfae.source) DESC
                ) AS rownum
          FROM  metabib.facet_entry mfae
                JOIN config.metabib_field cmf ON (cmf.id = mfae.field)
          WHERE mfae.source = ANY ($2)
                AND cmf.facet_field
                AND cmf.field_class NOT IN (SELECT * FROM unnest($1))
          GROUP by 1, 2
      ) all_facets
      WHERE rownum <= (
        SELECT COALESCE(
            (SELECT value::INT FROM config.global_flag WHERE name = 'search.max_facets_per_field' AND enabled),
            1000
        )
      );
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.facets_for_metarecord_set(ignore_facet_classes TEXT[], hits BIGINT[]) RETURNS TABLE (id INT, value TEXT, count BIGINT) AS $$
    SELECT id, value, count FROM (
        SELECT mfae.field AS id,
               mfae.value,
               COUNT(DISTINCT mmrsm.metarecord),
               row_number() OVER (
                PARTITION BY mfae.field ORDER BY COUNT(distinct mmrsm.metarecord) DESC
               ) AS rownum
        FROM metabib.facet_entry mfae
        JOIN metabib.metarecord_source_map mmrsm ON (mfae.source = mmrsm.source)
        JOIN config.metabib_field cmf ON (cmf.id = mfae.field)
        WHERE mmrsm.metarecord IN (SELECT * FROM unnest($2))
        AND cmf.facet_field
        AND cmf.field_class NOT IN (SELECT * FROM unnest($1))
        GROUP by 1, 2
    ) all_facets
    WHERE rownum <= (SELECT COALESCE((SELECT value::INT FROM config.global_flag WHERE name = 'search.max_facets_per_field' AND enabled), 1000));
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.calculate_visibility_attribute ( value INT, attr TEXT ) RETURNS INT AS $f$
SELECT  ((CASE $2

            WHEN 'luri_org'         THEN 0 -- "b" attr
            WHEN 'bib_source'       THEN 1 -- "b" attr

            WHEN 'copy_flags'       THEN 0 -- "c" attr
            WHEN 'owning_lib'       THEN 1 -- "c" attr
            WHEN 'circ_lib'         THEN 2 -- "c" attr
            WHEN 'status'           THEN 3 -- "c" attr
            WHEN 'location'         THEN 4 -- "c" attr
            WHEN 'location_group'   THEN 5 -- "c" attr

        END) << 28 ) | $1;

/* copy_flags bit positions, LSB-first:

 0: asset.copy.opac_visible


   When adding flags, you must update asset.all_visible_flags()

   Because bib and copy values are stored separately, we can reuse
   shifts, saving us some space. We could probably take back a bit
   too, but I'm not sure its worth squeezing that last one out. We'd
   be left with just 2 slots for copy attrs, rather than 10.
*/

$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION search.calculate_visibility_attribute_list ( attr TEXT, value INT[] ) RETURNS INT[] AS $f$
    SELECT ARRAY_AGG(search.calculate_visibility_attribute(x, $1)) FROM UNNEST($2) AS X;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION search.calculate_visibility_attribute_test ( attr TEXT, value INT[], negate BOOL DEFAULT FALSE ) RETURNS TEXT AS $f$
    SELECT  CASE WHEN $3 THEN '!' ELSE '' END || '(' || ARRAY_TO_STRING(search.calculate_visibility_attribute_list($1,$2),'|') || ')';
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.calculate_copy_visibility_attribute_set ( copy_id BIGINT ) RETURNS INT[] AS $f$
DECLARE
    copy_row    asset.copy%ROWTYPE;
    lgroup_map  asset.copy_location_group_map%ROWTYPE;
    attr_set    INT[] := '{}'::INT[];
BEGIN
    SELECT * INTO copy_row FROM asset.copy WHERE id = copy_id;

    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.opac_visible::INT, 'copy_flags');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.circ_lib, 'circ_lib');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.status, 'status');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.location, 'location');

    SELECT  ARRAY_APPEND(
                attr_set,
                search.calculate_visibility_attribute(owning_lib, 'owning_lib')
            ) INTO attr_set
      FROM  asset.call_number
      WHERE id = copy_row.call_number;

    FOR lgroup_map IN SELECT * FROM asset.copy_location_group_map WHERE location = copy_row.location LOOP
        attr_set := attr_set || search.calculate_visibility_attribute(lgroup_map.lgroup, 'location_group');
    END LOOP;

    RETURN attr_set;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.calculate_bib_visibility_attribute_set ( bib_id BIGINT, new_source INT DEFAULT NULL, force_source BOOL DEFAULT FALSE ) RETURNS INT[] AS $f$
DECLARE
    bib_row     biblio.record_entry%ROWTYPE;
    cn_row      asset.call_number%ROWTYPE;
    attr_set    INT[] := '{}'::INT[];
BEGIN
    SELECT * INTO bib_row FROM biblio.record_entry WHERE id = bib_id;

    IF force_source THEN
        IF new_source IS NOT NULL THEN
            attr_set := attr_set || search.calculate_visibility_attribute(new_source, 'bib_source');
        END IF;
    ELSIF bib_row.source IS NOT NULL THEN
        attr_set := attr_set || search.calculate_visibility_attribute(bib_row.source, 'bib_source');
    END IF;

    FOR cn_row IN
        SELECT  *
          FROM  asset.call_number
          WHERE record = bib_id
                AND label = '##URI##'
                AND NOT deleted
    LOOP
        attr_set := attr_set || search.calculate_visibility_attribute(cn_row.owning_lib, 'luri_org');
    END LOOP;

    RETURN attr_set;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    ocn     asset.call_number%ROWTYPE;
    ncn     asset.call_number%ROWTYPE;
    cid     BIGINT;
    dobib   BOOL;
BEGIN

    SELECT enabled = FALSE INTO dobib FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc';

    IF TG_TABLE_NAME = 'peer_bib_copy_map' THEN -- Only needs ON INSERT OR DELETE, so handle separately
        IF TG_OP = 'INSERT' THEN
            INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                NEW.peer_record,
                NEW.target_copy,
                asset.calculate_copy_visibility_attribute_set(NEW.target_copy)
            );

            RETURN NEW;
        ELSIF TG_OP = 'DELETE' THEN
            DELETE FROM asset.copy_vis_attr_cache
              WHERE record = OLD.peer_record AND target_copy = OLD.target_copy;

            RETURN OLD;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN -- Handles ON INSERT. ON UPDATE is below.
        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            SELECT * INTO ncn FROM asset.call_number cn WHERE id = NEW.call_number;
            INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                ncn.record,
                NEW.id,
                asset.calculate_copy_visibility_attribute_set(NEW.id)
            );
        ELSIF TG_TABLE_NAME = 'record_entry' THEN
            NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id, NEW.source, TRUE);
        ELSIF TG_TABLE_NAME = 'call_number' AND NEW.label = '##URI##' AND dobib THEN -- New located URI
            UPDATE  biblio.record_entry
              SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(NEW.record)
              WHERE id = NEW.record;

        END IF;

        RETURN NEW;
    END IF;

    -- handle items first, since with circulation activity
    -- their statuses change frequently
    IF TG_TABLE_NAME IN ('copy', 'unit') THEN -- This handles ON UPDATE OR DELETE. ON INSERT above

        IF TG_OP = 'DELETE' THEN -- Shouldn't get here, normally
            DELETE FROM asset.copy_vis_attr_cache WHERE target_copy = OLD.id;
            RETURN OLD;
        END IF;

        SELECT * INTO ncn FROM asset.call_number cn WHERE id = NEW.call_number;

        IF OLD.deleted <> NEW.deleted THEN
            IF NEW.deleted THEN
                DELETE FROM asset.copy_vis_attr_cache WHERE target_copy = OLD.id;
            ELSE
                INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                    ncn.record,
                    NEW.id,
                    asset.calculate_copy_visibility_attribute_set(NEW.id)
                );
            END IF;

            RETURN NEW;
        ELSIF OLD.location   <> NEW.location OR
            OLD.status       <> NEW.status OR
            OLD.opac_visible <> NEW.opac_visible OR
            OLD.circ_lib     <> NEW.circ_lib OR
            OLD.call_number  <> NEW.call_number
        THEN
            IF OLD.call_number  <> NEW.call_number THEN -- Special check since it's more expensive than the next branch
                SELECT * INTO ocn FROM asset.call_number cn WHERE id = OLD.call_number;

                IF ncn.record <> ocn.record THEN
                    -- We have to use a record-specific WHERE clause
                    -- to avoid modifying the entries for peer-bib copies.
                    UPDATE  asset.copy_vis_attr_cache
                      SET   target_copy = NEW.id,
                            record = ncn.record
                      WHERE target_copy = OLD.id
                            AND record = ocn.record;

                END IF;
            ELSE
                -- Any of these could change visibility, but
                -- we'll save some queries and not try to calculate
                -- the change directly.  We want to update peer-bib
                -- entries in this case, unlike above.
                UPDATE  asset.copy_vis_attr_cache
                  SET   target_copy = NEW.id,
                        vis_attr_vector = asset.calculate_copy_visibility_attribute_set(NEW.id)
                  WHERE target_copy = OLD.id;
            END IF;
        END IF;

    ELSIF TG_TABLE_NAME = 'call_number' THEN

        IF TG_OP = 'DELETE' AND OLD.label = '##URI##' AND dobib THEN -- really deleted located URI, if the delete protection rule is disabled...
            UPDATE  biblio.record_entry
              SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
              WHERE id = OLD.record;
            RETURN OLD;
        END IF;

        IF OLD.label = '##URI##' AND dobib THEN -- Located URI
            IF OLD.deleted <> NEW.deleted OR OLD.record <> NEW.record OR OLD.owning_lib <> NEW.owning_lib THEN
                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(NEW.record)
                  WHERE id = NEW.record;

                IF OLD.record <> NEW.record THEN -- maybe on merge?
                    UPDATE  biblio.record_entry
                      SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
                      WHERE id = OLD.record;
                END IF;
            END IF;

        ELSIF OLD.record <> NEW.record OR OLD.owning_lib <> NEW.owning_lib THEN
            UPDATE  asset.copy_vis_attr_cache
              SET   record = NEW.record,
                    vis_attr_vector = asset.calculate_copy_visibility_attribute_set(target_copy)
              WHERE target_copy IN (SELECT id FROM asset.copy WHERE call_number = NEW.id)
                    AND record = OLD.record;

        END IF;

    ELSIF TG_TABLE_NAME = 'record_entry' AND OLD.source IS DISTINCT FROM NEW.source THEN -- Only handles ON UPDATE, INSERT above
        NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id, NEW.source, TRUE);
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER z_opac_vis_mat_view_tgr BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR DELETE ON biblio.peer_bib_copy_map FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE OR DELETE ON asset.call_number FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_del_tgr BEFORE DELETE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_del_tgr BEFORE DELETE ON serial.unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON serial.unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();

CREATE OR REPLACE FUNCTION asset.all_visible_flags () RETURNS TEXT AS $f$
    SELECT  '(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(1 << x, 'copy_flags')),'&') || ')'
      FROM  GENERATE_SERIES(0,0) AS x; -- increment as new flags are added.
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.visible_orgs (otype TEXT) RETURNS TEXT AS $f$
    SELECT  '(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, $1)),'|') || ')'
      FROM  actor.org_unit
      WHERE opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.invisible_orgs (otype TEXT) RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, $1)),'|') || ')'
      FROM  actor.org_unit
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

-- Bib-oriented defaults for search
CREATE OR REPLACE FUNCTION asset.bib_source_default () RETURNS TEXT AS $f$
    SELECT  '(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'bib_source')),'|') || ')'
      FROM  config.bib_source
      WHERE transcendant;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.luri_org_default () RETURNS TEXT AS $f$
    SELECT  * FROM asset.invisible_orgs('luri_org');
$f$ LANGUAGE SQL STABLE;

-- Copy-oriented defaults for search
CREATE OR REPLACE FUNCTION asset.location_group_default () RETURNS TEXT AS $f$
    SELECT '!()'::TEXT; -- For now, as there's no way to cause a location group to hide all copies.
/*
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'location_group')),'|') || ')'
      FROM  asset.copy_location_group
      WHERE NOT opac_visible;
*/
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.location_default () RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'location')),'|') || ')'
      FROM  asset.copy_location
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.status_default () RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'status')),'|') || ')'
      FROM  config.copy_status
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.owning_lib_default () RETURNS TEXT AS $f$
    SELECT  * FROM asset.invisible_orgs('owning_lib');
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.circ_lib_default () RETURNS TEXT AS $f$
    SELECT  * FROM asset.invisible_orgs('circ_lib');
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.patron_default_visibility_mask () RETURNS TABLE (b_attrs TEXT, c_attrs TEXT)  AS $f$
DECLARE
    copy_flags      TEXT; -- "c" attr

    owning_lib      TEXT; -- "c" attr
    circ_lib        TEXT; -- "c" attr
    status          TEXT; -- "c" attr
    location        TEXT; -- "c" attr
    location_group  TEXT; -- "c" attr

    luri_org        TEXT; -- "b" attr
    bib_sources     TEXT; -- "b" attr

    bib_tests       TEXT := '';
BEGIN
    copy_flags      := asset.all_visible_flags(); -- Will always have at least one

    owning_lib      := NULLIF(asset.owning_lib_default(),'!()');

    circ_lib        := NULLIF(asset.circ_lib_default(),'!()');
    status          := NULLIF(asset.status_default(),'!()');
    location        := NULLIF(asset.location_default(),'!()');
    location_group  := NULLIF(asset.location_group_default(),'!()');

    -- LURIs will be handled at the perl layer directly
    -- luri_org        := NULLIF(asset.luri_org_default(),'!()');
    bib_sources     := NULLIF(asset.bib_source_default(),'()');


    IF luri_org IS NOT NULL AND bib_sources IS NOT NULL THEN
        bib_tests := '('||ARRAY_TO_STRING( ARRAY[luri_org,bib_sources], '|')||')&('||luri_org||')&';
    ELSIF luri_org IS NOT NULL THEN
        bib_tests := luri_org || '&';
    ELSIF bib_sources IS NOT NULL THEN
        bib_tests := bib_sources || '|';
    END IF;

    RETURN QUERY SELECT bib_tests,
        '('||ARRAY_TO_STRING(
            ARRAY[copy_flags,owning_lib,circ_lib,status,location,location_group]::TEXT[],
            '&'
        )||')';
END;
$f$ LANGUAGE PLPGSQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION metabib.suggest_browse_entries(raw_query_text text, search_class text, headline_opts text, visibility_org integer, query_limit integer, normalization integer)
 RETURNS TABLE(value text, field integer, buoyant_and_class_match boolean, field_match boolean, field_weight integer, rank real, buoyant boolean, match text)
AS $f$
DECLARE
    prepared_query_texts    TEXT[];
    query                   TSQUERY;
    plain_query             TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
    b_tests                 TEXT := '';
BEGIN
    prepared_query_texts := metabib.autosuggest_prepare_tsquery(raw_query_text);

    query := TO_TSQUERY('keyword', prepared_query_texts[1]);
    plain_query := TO_TSQUERY('keyword', prepared_query_texts[2]);

    visibility_org := NULLIF(visibility_org,-1);
    IF visibility_org IS NOT NULL THEN
        PERFORM FROM actor.org_unit WHERE id = visibility_org AND parent_ou IS NULL;
        IF FOUND THEN
            opac_visibility_join := '';
        ELSE
            PERFORM 1 FROM config.internal_flag WHERE enabled AND name = 'opac.located_uri.act_as_copy';
            IF FOUND THEN
                b_tests := search.calculate_visibility_attribute_test(
                    'luri_org',
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_full_path(visibility_org))
                );
            ELSE
                b_tests := search.calculate_visibility_attribute_test(
                    'luri_org',
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_ancestors(visibility_org))
                );
            END IF;
            opac_visibility_join := '
    LEFT JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = x.source)
    LEFT JOIN biblio.record_entry b ON (b.id = x.source)
    JOIN vm ON (acvac.vis_attr_vector @@
            (vm.c_attrs || $$&$$ ||
                search.calculate_visibility_attribute_test(
                    $$circ_lib$$,
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_descendants($4))
                )
            )::query_int
         ) OR (b.vis_attr_vector @@ $$' || b_tests || '$$::query_int)
';
        END IF;
    ELSE
        opac_visibility_join := '';
    END IF;

    -- The following determines whether we only provide suggestsons matching
    -- the user's selected search_class, or whether we show other suggestions
    -- too. The reason for MIN() is that for search_classes like
    -- 'title|proper|uniform' you would otherwise get multiple rows.  The
    -- implication is that if title as a class doesn't have restrict,
    -- nor does the proper field, but the uniform field does, you're going
    -- to get 'false' for your overall evaluation of 'should we restrict?'
    -- To invert that, change from MIN() to MAX().

    SELECT
        INTO r_fields
            MIN(cmc.restrict::INT) AS restrict_class,
            MIN(cmf.restrict::INT) AS restrict_field
        FROM metabib.search_class_to_registered_components(search_class)
            AS _registered (field_class TEXT, field INT)
        JOIN
            config.metabib_class cmc ON (cmc.name = _registered.field_class)
        LEFT JOIN
            config.metabib_field cmf ON (cmf.id = _registered.field);

    -- evaluate 'should we restrict?'
    IF r_fields.restrict_field::BOOL OR r_fields.restrict_class::BOOL THEN
        search_class_join := '
    JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            (_registered.field IS NULL AND
                _registered.field_class = cmf.field_class) OR
            (_registered.field = cmf.id)
        )
    ';
    ELSE
        search_class_join := '
    LEFT JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            _registered.field_class = cmc.name
        )
    ';
    END IF;

    RETURN QUERY EXECUTE '
WITH vm AS ( SELECT * FROM asset.patron_default_visibility_mask() ),
     mbe AS (SELECT * FROM metabib.browse_entry WHERE index_vector @@ $1 LIMIT 10000)
SELECT  DISTINCT
        x.value,
        x.id,
        x.push,
        x.restrict,
        x.weight,
        x.ts_rank_cd,
        x.buoyant,
        TS_HEADLINE(value, $7, $3)
  FROM  (SELECT DISTINCT
                mbe.value,
                cmf.id,
                cmc.buoyant AND _registered.field_class IS NOT NULL AS push,
                _registered.field = cmf.id AS restrict,
                cmf.weight,
                TS_RANK_CD(mbe.index_vector, $1, $6),
                cmc.buoyant,
                mbedm.source
          FROM  metabib.browse_entry_def_map mbedm
                JOIN mbe ON (mbe.id = mbedm.entry)
                JOIN config.metabib_field cmf ON (cmf.id = mbedm.def)
                JOIN config.metabib_class cmc ON (cmf.field_class = cmc.name)
                '  || search_class_join || '
          ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
          LIMIT 1000) AS x
        ' || opac_visibility_join || '
  ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
  LIMIT $5
'   -- sic, repeat the order by clause in the outer select too
    USING
        query, search_class, headline_opts,
        visibility_org, query_limit, normalization, plain_query
        ;

    -- sort order:
    --  buoyant AND chosen class = match class
    --  chosen field = match field
    --  field weight
    --  rank
    --  buoyancy
    --  value itself

END;
$f$ LANGUAGE plpgsql ROWS 10;

CREATE OR REPLACE FUNCTION metabib.staged_browse(query text, fields integer[], context_org integer, context_locations integer[], staff boolean, browse_superpage_size integer, count_up_from_zero boolean, result_limit integer, next_pivot_pos integer)
 RETURNS SETOF metabib.flat_browse_entry_appearance
AS $f$
DECLARE
    curs                    REFCURSOR;
    rec                     RECORD;
    qpfts_query             TEXT;
    aqpfts_query            TEXT;
    afields                 INT[];
    bfields                 INT[];
    result_row              metabib.flat_browse_entry_appearance%ROWTYPE;
    results_skipped         INT := 0;
    row_counter             INT := 0;
    row_number              INT;
    slice_start             INT;
    slice_end               INT;
    full_end                INT;
    all_records             BIGINT[];
    all_brecords             BIGINT[];
    all_arecords            BIGINT[];
    superpage_of_records    BIGINT[];
    superpage_size          INT;
    c_tests                 TEXT := '';
    b_tests                 TEXT := '';
    c_orgs                  INT[];
    unauthorized_entry      RECORD;
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    IF NOT staff THEN
        SELECT x.c_attrs, x.b_attrs INTO c_tests, b_tests FROM asset.patron_default_visibility_mask() x;
    END IF;

    -- b_tests supplies its own query_int operator, c_tests does not
    IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;

    SELECT ARRAY_AGG(id) INTO c_orgs FROM actor.org_unit_descendants(context_org);

    c_tests := c_tests || search.calculate_visibility_attribute_test('circ_lib',c_orgs)
               || '&' || search.calculate_visibility_attribute_test('owning_lib',c_orgs);

    PERFORM 1 FROM config.internal_flag WHERE enabled AND name = 'opac.located_uri.act_as_copy';
    IF FOUND THEN
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_full_path(context_org) x)
        );
    ELSE
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_ancestors(context_org) x)
        );
    END IF;

    IF context_locations THEN
        IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;
        c_tests := c_tests || search.calculate_visibility_attribute_test('location',context_locations);
    END IF;

    OPEN curs NO SCROLL FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;

        --Is unauthorized?
        SELECT INTO unauthorized_entry *
        FROM metabib.browse_entry_simple_heading_map mbeshm
        INNER JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
        INNER JOIN authority.control_set_authority_field acsaf ON ( acsaf.id = ash.atag )
        JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
        WHERE mbeshm.entry = rec.id
        AND   ahf.heading_purpose = 'variant';

        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
        IF (unauthorized_entry.record IS NOT NULL) THEN
            --unauthorized term belongs to an auth linked to a bib?
            SELECT INTO all_arecords, result_row.sees, afields
                    ARRAY_AGG(DISTINCT abl.bib),
                    STRING_AGG(DISTINCT abl.authority::TEXT, $$,$$),
                    ARRAY_AGG(DISTINCT map.metabib_field)
            FROM authority.bib_linking abl
            INNER JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                    map.authority_field = unauthorized_entry.atag
                    AND map.metabib_field = ANY(fields)
            )
            WHERE abl.authority = unauthorized_entry.record;
        ELSE
            --do usual procedure
            SELECT INTO all_arecords, result_row.sees, afields
                    ARRAY_AGG(DISTINCT abl.bib), -- bibs to check for visibility
                    STRING_AGG(DISTINCT aal.source::TEXT, $$,$$), -- authority record ids
                    ARRAY_AGG(DISTINCT map.metabib_field) -- authority-tag-linked CMF rows

            FROM  metabib.browse_entry_simple_heading_map mbeshm
                    JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                    JOIN authority.authority_linking aal ON ( ash.record = aal.source )
                    JOIN authority.bib_linking abl ON ( aal.target = abl.authority )
                    JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                        ash.atag = map.authority_field
                        AND map.metabib_field = ANY(fields)
                    )
                    JOIN authority.control_set_authority_field acsaf ON (
                        map.authority_field = acsaf.id
                    )
                    JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
              WHERE mbeshm.entry = rec.id
              AND   ahf.heading_purpose = 'variant';

        END IF;

        -- Gather aggregate data based on the MBE row we're looking at now, bib axis
        SELECT INTO all_brecords, result_row.authorities, bfields
                ARRAY_AGG(DISTINCT source),
                STRING_AGG(DISTINCT authority::TEXT, $$,$$),
                ARRAY_AGG(DISTINCT def)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        SELECT INTO result_row.fields STRING_AGG(DISTINCT x::TEXT, $$,$$) FROM UNNEST(afields || bfields) x;

        result_row.sources := 0;
        result_row.asources := 0;

        -- Bib-linked vis checking
        IF ARRAY_UPPER(all_brecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.sources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    LEFT JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_brecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.accurate := TRUE;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.asources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    LEFT JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_arecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.aaccurate := TRUE;

        END IF;

        IF result_row.sources > 0 OR result_row.asources > 0 THEN

            -- The function that calls this function needs row_number in order
            -- to correctly order results from two different runs of this
            -- functions.
            result_row.row_number := row_number;

            -- Now, if row_counter is still less than limit, return a row.  If
            -- not, but it is less than next_pivot_pos, continue on without
            -- returning actual result rows until we find
            -- that next pivot, and return it.

            IF row_counter < result_limit THEN
                result_row.browse_entry := rec.id;
                result_row.value := rec.value;

                RETURN NEXT result_row;
            ELSE
                result_row.browse_entry := NULL;
                result_row.authorities := NULL;
                result_row.fields := NULL;
                result_row.value := NULL;
                result_row.sources := NULL;
                result_row.sees := NULL;
                result_row.accurate := NULL;
                result_row.aaccurate := NULL;
                result_row.pivot_point := rec.id;

                IF row_counter >= next_pivot_pos THEN
                    RETURN NEXT result_row;
                    RETURN;
                END IF;
            END IF;

            IF count_up_from_zero THEN
                row_number := row_number + 1;
            ELSE
                row_number := row_number - 1;
            END IF;

            -- row_counter is different from row_number.
            -- It simply counts up from zero so that we know when
            -- we've reached our limit.
            row_counter := row_counter + 1;
        END IF;
    END LOOP;
END;
$f$ LANGUAGE plpgsql ROWS 10;

CREATE OR REPLACE FUNCTION metabib.browse(search_field integer[], browse_term text, context_org integer DEFAULT NULL::integer, context_loc_group integer DEFAULT NULL::integer, staff boolean DEFAULT false, pivot_id bigint DEFAULT NULL::bigint, result_limit integer DEFAULT 10)
 RETURNS SETOF metabib.flat_browse_entry_appearance
AS $f$
DECLARE
    core_query              TEXT;
    back_query              TEXT;
    forward_query           TEXT;
    pivot_sort_value        TEXT;
    pivot_sort_fallback     TEXT;
    context_locations       INT[];
    browse_superpage_size   INT;
    results_skipped         INT := 0;
    back_limit              INT;
    back_to_pivot           INT;
    forward_limit           INT;
    forward_to_pivot        INT;
BEGIN
    -- First, find the pivot if we were given a browse term but not a pivot.
    IF pivot_id IS NULL THEN
        pivot_id := metabib.browse_pivot(search_field, browse_term);
    END IF;

    SELECT INTO pivot_sort_value, pivot_sort_fallback
        sort_value, value FROM metabib.browse_entry WHERE id = pivot_id;

    -- Bail if we couldn't find a pivot.
    IF pivot_sort_value IS NULL THEN
        RETURN;
    END IF;

    -- Transform the context_loc_group argument (if any) (logc at the
    -- TPAC layer) into a form we'll be able to use.
    IF context_loc_group IS NOT NULL THEN
        SELECT INTO context_locations ARRAY_AGG(location)
            FROM asset.copy_location_group_map
            WHERE lgroup = context_loc_group;
    END IF;

    -- Get the configured size of browse superpages.
    SELECT INTO browse_superpage_size COALESCE(value::INT,100)     -- NULL ok
        FROM config.global_flag
        WHERE enabled AND name = 'opac.browse.holdings_visibility_test_limit';

    -- First we're going to search backward from the pivot, then we're going
    -- to search forward.  In each direction, we need two limits.  At the
    -- lesser of the two limits, we delineate the edge of the result set
    -- we're going to return.  At the greater of the two limits, we find the
    -- pivot value that would represent an offset from the current pivot
    -- at a distance of one "page" in either direction, where a "page" is a
    -- result set of the size specified in the "result_limit" argument.
    --
    -- The two limits in each direction make four derived values in total,
    -- and we calculate them now.
    back_limit := CEIL(result_limit::FLOAT / 2);
    back_to_pivot := result_limit;
    forward_limit := result_limit / 2;
    forward_to_pivot := result_limit - 1;

    -- This is the meat of the SQL query that finds browse entries.  We'll
    -- pass this to a function which uses it with a cursor, so that individual
    -- rows may be fetched in a loop until some condition is satisfied, without
    -- waiting for a result set of fixed size to be collected all at once.
    core_query := '
SELECT  mbe.id,
        mbe.value,
        mbe.sort_value
  FROM  metabib.browse_entry mbe
  WHERE (
            EXISTS ( -- are there any bibs using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_def_map mbedm
                  WHERE mbedm.entry = mbe.id AND mbedm.def = ANY(' || quote_literal(search_field) || ')
            ) OR EXISTS ( -- are there any authorities using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_simple_heading_map mbeshm
                        JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                        JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                            ash.atag = map.authority_field
                            AND map.metabib_field = ANY(' || quote_literal(search_field) || ')
                        )
                        JOIN authority.control_set_authority_field acsaf ON (
                            map.authority_field = acsaf.id
                        )
                        JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
                  WHERE mbeshm.entry = mbe.id
                    AND ahf.heading_purpose IN (' || $$'variant'$$ || ')
                    -- and authority that variant is coming from is linked to a bib
                    AND EXISTS (
                        SELECT  1
                        FROM  metabib.browse_entry_def_map mbedm2
                        WHERE mbedm2.authority = ash.record AND mbedm2.def = ANY(' || quote_literal(search_field) || ')
                    )

            )
        ) AND ';

    -- This is the variant of the query for browsing backward.
    back_query := core_query ||
        ' mbe.sort_value <= ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value DESC, mbe.value DESC LIMIT 1000';

    -- This variant browses forward.
    forward_query := core_query ||
        ' mbe.sort_value > ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value, mbe.value LIMIT 1000';

    -- We now call the function which applies a cursor to the provided
    -- queries, stopping at the appropriate limits and also giving us
    -- the next page's pivot.
    RETURN QUERY
        SELECT * FROM metabib.staged_browse(
            back_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, TRUE, back_limit, back_to_pivot
        ) UNION
        SELECT * FROM metabib.staged_browse(
            forward_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, FALSE, forward_limit, forward_to_pivot
        ) ORDER BY row_number DESC;

END;
$f$ LANGUAGE plpgsql ROWS 10;

CREATE OR REPLACE FUNCTION metabib.browse(
    search_class        TEXT,
    browse_term         TEXT,
    context_org         INT DEFAULT NULL,
    context_loc_group   INT DEFAULT NULL,
    staff               BOOL DEFAULT FALSE,
    pivot_id            BIGINT DEFAULT NULL,
    result_limit        INT DEFAULT 10
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
BEGIN
    RETURN QUERY SELECT * FROM metabib.browse(
        (SELECT COALESCE(ARRAY_AGG(id), ARRAY[]::INT[])
            FROM config.metabib_field WHERE field_class = search_class),
        browse_term,
        context_org,
        context_loc_group,
        staff,
        pivot_id,
        result_limit
    );
END;
$p$ LANGUAGE PLPGSQL ROWS 10;

CREATE OR REPLACE VIEW search.best_tsconfig AS
    SELECT  m.id AS id,
            COALESCE(f.ts_config, c.ts_config, 'simple') AS ts_config
      FROM  config.metabib_field m
            LEFT JOIN config.metabib_class_ts_map c ON (c.field_class = m.field_class AND c.index_weight = 'C')
            LEFT JOIN config.metabib_field_ts_map f ON (f.metabib_field = m.id AND f.index_weight = 'C');

CREATE TYPE search.highlight_result AS ( id BIGINT, source BIGINT, field INT, value TEXT, highlight TEXT );

CREATE OR REPLACE FUNCTION search.highlight_display_fields_impl(
    rid         BIGINT,
    tsq         TEXT,
    field_list  INT[] DEFAULT '{}'::INT[],
    css_class   TEXT DEFAULT 'oils_SH',
    hl_all      BOOL DEFAULT TRUE,
    minwords    INT DEFAULT 5,
    maxwords    INT DEFAULT 25,
    shortwords  INT DEFAULT 0,
    maxfrags    INT DEFAULT 0,
    delimiter   TEXT DEFAULT ' ... '
) RETURNS SETOF search.highlight_result AS $f$
DECLARE
    opts            TEXT := '';
    v_css_class     TEXT := css_class;
    v_delimiter     TEXT := delimiter;
    v_field_list    INT[] := field_list;
    hl_query        TEXT;
BEGIN
    IF v_delimiter LIKE $$%'%$$ OR v_delimiter LIKE '%"%' THEN --"
        v_delimiter := ' ... ';
    END IF;

    IF NOT hl_all THEN
        opts := opts || 'MinWords=' || minwords;
        opts := opts || ', MaxWords=' || maxwords;
        opts := opts || ', ShortWords=' || shortwords;
        opts := opts || ', MaxFragments=' || maxfrags;
        opts := opts || ', FragmentDelimiter="' || delimiter || '"';
    ELSE
        opts := opts || 'HighlightAll=TRUE';
    END IF;

    IF v_css_class LIKE $$%'%$$ OR v_css_class LIKE '%"%' THEN -- "
        v_css_class := 'oils_SH';
    END IF;

    opts := opts || $$, StopSel=</b>, StartSel="<b class='$$ || v_css_class; -- "

    IF v_field_list = '{}'::INT[] THEN
        SELECT ARRAY_AGG(id) INTO v_field_list FROM config.metabib_field WHERE display_field;
    END IF;

    hl_query := $$
        SELECT  de.id,
                de.source,
                de.field,
                de.value AS value,
                ts_headline(
                    ts_config::REGCONFIG,
                    evergreen.escape_for_html(de.value),
                    $$ || quote_literal(tsq) || $$,
                    $1 || ' ' || mf.field_class || ' ' || mf.name || $xx$'>"$xx$ -- "'
                ) AS highlight
          FROM  metabib.display_entry de
                JOIN config.metabib_field mf ON (mf.id = de.field)
                JOIN search.best_tsconfig t ON (t.id = de.field)
          WHERE de.source = $2
                AND field = ANY ($3)
          ORDER BY de.id;$$;

    RETURN QUERY EXECUTE hl_query USING opts, rid, v_field_list;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.escape_for_html (TEXT) RETURNS TEXT AS $$
    SELECT  regexp_replace(
                regexp_replace(
                    regexp_replace(
                        $1,
                        '&',
                        '&amp;',
                        'g'
                    ),
                    '<',
                    '&lt;',
                    'g'
                ),
                '>',
                '&gt;',
                'g'
            );
$$ LANGUAGE SQL IMMUTABLE LEAKPROOF STRICT COST 10;

CREATE OR REPLACE FUNCTION search.highlight_display_fields(
    rid         BIGINT,
    tsq_map     TEXT, -- { '(a | b) & c' => '1,2,3,4', ...}
    css_class   TEXT DEFAULT 'oils_SH',
    hl_all      BOOL DEFAULT TRUE,
    minwords    INT DEFAULT 5,
    maxwords    INT DEFAULT 25,
    shortwords  INT DEFAULT 0,
    maxfrags    INT DEFAULT 0,
    delimiter   TEXT DEFAULT ' ... '
) RETURNS SETOF search.highlight_result AS $f$
DECLARE
    tsq_hstore  TEXT;
    tsq         TEXT;
    fields      TEXT;
    afields     INT[];
    seen        INT[];
BEGIN
    IF (tsq_map ILIKE 'hstore%') THEN
        EXECUTE 'SELECT ' || tsq_map INTO tsq_hstore;
    ELSE
        tsq_hstore := tsq_map::HSTORE;
    END IF;

    FOR tsq, fields IN SELECT key, value FROM each(tsq_hstore::HSTORE) LOOP
        SELECT  ARRAY_AGG(unnest::INT) INTO afields
          FROM  unnest(regexp_split_to_array(fields,','));
        seen := seen || afields;

        RETURN QUERY
            SELECT * FROM search.highlight_display_fields_impl(
                rid, tsq, afields, css_class, hl_all,minwords,
                maxwords, shortwords, maxfrags, delimiter
            );
    END LOOP;

    RETURN QUERY
        SELECT  id,
                source,
                field,
                value,
                value AS highlight
          FROM  metabib.display_entry
          WHERE source = rid
                AND NOT (field = ANY (seen));
END;
$f$ LANGUAGE PLPGSQL ROWS 10;

COMMIT;

