/*
 * Copyright (C) 2016 Equinox Software, Inc.
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


BEGIN;

SELECT evergreen.upgrade_deps_block_check('0984', :eg_version);

ALTER TYPE search.search_result ADD ATTRIBUTE badges TEXT, ADD ATTRIBUTE popularity NUMERIC;

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
 
CREATE OR REPLACE FUNCTION metabib.staged_browse(
    query                   TEXT,
    fields                  INT[],
    context_org             INT,
    context_locations       INT[],
    staff                   BOOL,
    browse_superpage_size   INT,
    count_up_from_zero      BOOL,   -- if false, count down from -1
    result_limit            INT,
    next_pivot_pos          INT
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
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
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    OPEN curs FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;


        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
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
          WHERE mbeshm.entry = rec.id;


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

            full_end := ARRAY_LENGTH(all_brecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.sources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_brecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    'NULL AS badges, NULL::NUMERIC AS popularity, ' ||
                    '1::NUMERIC AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, until we've
                -- either exhausted that set of records or found at least 1
                -- visible record.

                SELECT INTO result_row.sources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;

            -- Accurate?  Well, probably.
            result_row.accurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            full_end := ARRAY_LENGTH(all_arecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.asources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_arecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    'NULL AS badges, NULL::NUMERIC AS popularity, ' ||
                    '1::NUMERIC AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, via
                -- authority until we've either exhausted that set of records
                -- or found at least 1 visible record.

                SELECT INTO result_row.asources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;


            -- Accurate?  Well, probably.
            result_row.aaccurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

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
$p$ LANGUAGE PLPGSQL;

COMMIT;

