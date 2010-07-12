BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0332'); -- gmc

CREATE TABLE asset.opac_visible_copies (
  id        BIGINT primary key, -- copy id
  record    BIGINT,
  circ_lib  INTEGER
);
COMMENT ON TABLE asset.opac_visible_copies IS $$
Materialized view of copies that are visible in the OPAC, used by
search.query_parser_fts() to speed up OPAC visibility checks on large
databases.  Contents are maintained by a set of triggers.
$$;
CREATE INDEX opac_visible_copies_idx1 on asset.opac_visible_copies (record, circ_lib);

-- copy OPAC visibility materialized view
CREATE OR REPLACE FUNCTION asset.refresh_opac_visible_copies_mat_view () RETURNS VOID AS $$

    TRUNCATE TABLE asset.opac_visible_copies;

    INSERT INTO asset.opac_visible_copies (id, circ_lib, record)
    SELECT  cp.id, cp.circ_lib, cn.record
    FROM  asset.copy cp
        JOIN asset.call_number cn ON (cn.id = cp.call_number)
        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
        JOIN asset.copy_location cl ON (cp.location = cl.id)
        JOIN config.copy_status cs ON (cp.status = cs.id)
        JOIN biblio.record_entry b ON (cn.record = b.id)
    WHERE NOT cp.deleted
        AND NOT cn.deleted
        AND NOT b.deleted
        AND cs.opac_visible
        AND cl.opac_visible
        AND cp.opac_visible
        AND a.opac_visible;

$$ LANGUAGE SQL;
COMMENT ON FUNCTION asset.refresh_opac_visible_copies_mat_view() IS $$
Rebuild the copy OPAC visibility cache.  Useful during migrations.
$$;

-- and actually populate the table
SELECT asset.refresh_opac_visible_copies_mat_view();

CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    add_query       TEXT;
    remove_query    TEXT;
    do_add          BOOLEAN := false;
    do_remove       BOOLEAN := false;
BEGIN
    add_query := $$
            INSERT INTO asset.opac_visible_copies (id, circ_lib, record)
                SELECT  cp.id, cp.circ_lib, cn.record
                  FROM  asset.copy cp
                        JOIN asset.call_number cn ON (cn.id = cp.call_number)
                        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                        JOIN asset.copy_location cl ON (cp.location = cl.id)
                        JOIN config.copy_status cs ON (cp.status = cs.id)
                        JOIN biblio.record_entry b ON (cn.record = b.id)
                  WHERE NOT cp.deleted
                        AND NOT cn.deleted
                        AND NOT b.deleted
                        AND cs.opac_visible
                        AND cl.opac_visible
                        AND cp.opac_visible
                        AND a.opac_visible
    $$;
 
    remove_query := $$ DELETE FROM asset.opac_visible_copies WHERE id IN ( SELECT id FROM asset.copy WHERE $$;

    IF TG_OP = 'INSERT' THEN

        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            add_query := add_query || 'AND cp.id = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    -- handle items first, since with circulation activity
    -- their statuses change frequently
    IF TG_TABLE_NAME IN ('copy', 'unit') THEN

        IF OLD.location    <> NEW.location OR
           OLD.call_number <> NEW.call_number OR
           OLD.status      <> NEW.status OR
           OLD.circ_lib    <> NEW.circ_lib THEN
            -- any of these could change visibility, but
            -- we'll save some queries and not try to calculate
            -- the change directly
            do_remove := true;
            do_add := true;
        ELSE

            IF OLD.deleted <> NEW.deleted THEN
                IF NEW.deleted THEN
                    do_remove := true;
                ELSE
                    do_add := true;
                END IF;
            END IF;

            IF OLD.opac_visible <> NEW.opac_visible THEN
                IF OLD.opac_visible THEN
                    do_remove := true;
                ELSIF NOT do_remove THEN -- handle edge case where deleted item
                                        -- is also marked opac_visible
                    do_add := true;
                END IF;
            END IF;

        END IF;

        IF do_remove THEN
            DELETE FROM asset.opac_visible_copies WHERE id = NEW.id;
        END IF;
        IF do_add THEN
            add_query := add_query || 'AND cp.id = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('call_number', 'record_entry') THEN -- these have a 'deleted' column
 
        IF OLD.deleted AND NEW.deleted THEN -- do nothing

            RETURN NEW;
 
        ELSIF NEW.deleted THEN -- remove rows
 
            IF TG_TABLE_NAME = 'call_number' THEN
                DELETE FROM asset.opac_visible_copies WHERE id IN (SELECT id FROM asset.copy WHERE call_number = NEW.id);
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                DELETE FROM asset.opac_visible_copies WHERE record = NEW.id;
            END IF;
 
            RETURN NEW;
 
        ELSIF OLD.deleted THEN -- add rows
 
            IF TG_TABLE_NAME IN ('copy','unit') THEN
                add_query := add_query || 'AND cp.id = ' || NEW.id || ';';
            ELSIF TG_TABLE_NAME = 'call_number' THEN
                add_query := add_query || 'AND cp.call_number = ' || NEW.id || ';';
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                add_query := add_query || 'AND cn.record = ' || NEW.id || ';';
            END IF;
 
            EXECUTE add_query;
            RETURN NEW;
 
        END IF;
 
    END IF;

    IF TG_TABLE_NAME = 'call_number' THEN

        IF OLD.record <> NEW.record THEN
            -- call number is linked to different bib
            remove_query := remove_query || 'call_number = ' || NEW.id || ');';
            EXECUTE remove_query;
            add_query := add_query || 'AND cp.call_number = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('record_entry') THEN
        RETURN NEW; -- don't have 'opac_visible'
    END IF;

    -- actor.org_unit, asset.copy_location, asset.copy_status
    IF NEW.opac_visible = OLD.opac_visible THEN -- do nothing

        RETURN NEW;

    ELSIF NEW.opac_visible THEN -- add rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            add_query := add_query || 'AND cp.circ_lib = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            add_query := add_query || 'AND cp.location = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            add_query := add_query || 'AND cp.status = ' || NEW.id || ';';
        END IF;
 
        EXECUTE add_query;
 
    ELSE -- delete rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            remove_query := 'DELETE FROM asset.opac_visible_copies WHERE circ_lib = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            remove_query := remove_query || 'location = ' || NEW.id || ');';
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            remove_query := remove_query || 'status = ' || NEW.id || ');';
        END IF;
 
        EXECUTE remove_query;
 
    END IF;
 
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;
COMMENT ON FUNCTION asset.cache_copy_visibility() IS $$
Trigger function to update the copy OPAC visiblity cache.
$$;
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON asset.call_number FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON asset.copy_location FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON serial.unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON config.copy_status FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON actor.org_unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();

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
    staff           BOOL
 
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];

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
    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;
    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

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
              FROM  asset.opac_visible_copies
              WHERE circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND record IN ( SELECT * FROM search.explode_array( core_result.records ) )
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

COMMIT;
