BEGIN;

--Check if we can apply the upgrade.
SELECT evergreen.upgrade_deps_block_check('0791', :eg_version);



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

BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;

        SELECT array_accum(distinct id) INTO luri_org_list FROM actor.org_unit_ancestors( param_search_ou );

    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;

        FOR tmp_int IN SELECT * FROM UNNEST(search_org_list) LOOP
            SELECT array_accum(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( tmp_int );
            luri_org_list := luri_org_list || tmp_int_list;
        END LOOP;

        SELECT array_accum(DISTINCT x.id) INTO luri_org_list FROM UNNEST(luri_org_list) x(id);

    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    IF param_pref_ou IS NOT NULL THEN
        SELECT array_accum(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors(param_pref_ou);
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

                        IF FOUND THEN
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


-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;
        IF NOT FOUND THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id;
            DELETE FROM metabib.record_attr WHERE id = NEW.id;
        END IF;

        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            FOR attr_def IN SELECT * FROM config.record_attr_definition ORDER BY format LOOP

                IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
                    SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(value), COALESCE(attr_def.joiner,' ')) INTO attr_value
                      FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
                      WHERE record = NEW.id
                            AND tag LIKE attr_def.tag
                            AND CASE
                                WHEN attr_def.sf_list IS NOT NULL 
                                    THEN POSITION(subfield IN attr_def.sf_list) > 0
                                ELSE TRUE
                                END
                      GROUP BY tag
                      ORDER BY tag
                      LIMIT 1;

                ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
                    attr_value := biblio.marc21_extract_fixed_field(NEW.id, attr_def.fixed_field);

                ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

                    SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
            
                    -- See if we can skip the XSLT ... it's expensive
                    IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                        -- Can't skip the transform
                        IF xfrm.xslt <> '---' THEN
                            transformed_xml := oils_xslt_process(NEW.marc,xfrm.xslt);
                        ELSE
                            transformed_xml := NEW.marc;
                        END IF;
            
                        prev_xfrm := xfrm.name;
                    END IF;

                    IF xfrm.name IS NULL THEN
                        -- just grab the marcxml (empty) transform
                        SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                        prev_xfrm := xfrm.name;
                    END IF;

                    attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

                ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
                    SELECT  m.value INTO attr_value
                      FROM  biblio.marc21_physical_characteristics(NEW.id) v
                            JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
                      WHERE v.subfield = attr_def.phys_char_sf
                      LIMIT 1; -- Just in case ...

                END IF;

                -- apply index normalizers to attr_value
                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                      FROM  config.index_normalizer n
                            JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                      WHERE attr = attr_def.name
                      ORDER BY m.pos LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            COALESCE( quote_literal( attr_value ), 'NULL' ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO attr_value;
        
                END LOOP;

                -- Add the new value to the hstore
                new_attrs := new_attrs || hstore( attr_def.name, attr_value );

            END LOOP;

            IF TG_OP = 'INSERT' OR OLD.deleted THEN -- initial insert OR revivication
                DELETE FROM metabib.record_attr WHERE id = NEW.id;
                INSERT INTO metabib.record_attr (id, attrs) VALUES (NEW.id, new_attrs);
            ELSE
                UPDATE metabib.record_attr SET attrs = new_attrs WHERE id = NEW.id;
            END IF;

        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;
 
COMMIT;
