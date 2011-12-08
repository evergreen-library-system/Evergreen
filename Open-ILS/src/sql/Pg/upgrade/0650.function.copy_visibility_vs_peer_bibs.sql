-- Evergreen DB patch 0650.function.copy_visibility_vs_peer_bibs.sql
--
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0650', :eg_version);

CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    add_front       TEXT;
    add_back        TEXT;
    add_base_query  TEXT;
    add_peer_query  TEXT;
    remove_query    TEXT;
    do_add          BOOLEAN := false;
    do_remove       BOOLEAN := false;
BEGIN
    add_base_query := $$
        SELECT  cp.id, cp.circ_lib, cn.record, cn.id AS call_number, cp.location, cp.status
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
    add_peer_query := $$
        SELECT  cp.id, cp.circ_lib, pbcm.peer_record AS record, NULL AS call_number, cp.location, cp.status
          FROM  asset.copy cp
                JOIN biblio.peer_bib_copy_map pbcm ON (pbcm.target_copy = cp.id)
                JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                JOIN asset.copy_location cl ON (cp.location = cl.id)
                JOIN config.copy_status cs ON (cp.status = cs.id)
          WHERE NOT cp.deleted
                AND cs.opac_visible
                AND cl.opac_visible
                AND cp.opac_visible
                AND a.opac_visible
    $$;
    add_front := $$
        INSERT INTO asset.opac_visible_copies (copy_id, circ_lib, record)
          SELECT DISTINCT ON (id, record) id, circ_lib, record FROM (
    $$;
    add_back := $$
        ) AS x
    $$;
 
    remove_query := $$ DELETE FROM asset.opac_visible_copies WHERE copy_id IN ( SELECT id FROM asset.copy WHERE $$;

    IF TG_TABLE_NAME = 'peer_bib_copy_map' THEN
        IF TG_OP = 'INSERT' THEN
            add_peer_query := add_peer_query || ' AND cp.id = ' || NEW.target_copy || ' AND pbcm.peer_record = ' || NEW.peer_record;
            EXECUTE add_front || add_peer_query || add_back;
            RETURN NEW;
        ELSE
            remove_query := 'DELETE FROM asset.opac_visible_copies WHERE copy_id = ' || OLD.target_copy || ' AND record = ' || OLD.peer_record || ';';
            EXECUTE remove_query;
            RETURN OLD;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN

        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            add_base_query := add_base_query || ' AND cp.id = ' || NEW.id;
            EXECUTE add_front || add_base_query || add_back;
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
            DELETE FROM asset.opac_visible_copies WHERE copy_id = NEW.id;
        END IF;
        IF do_add THEN
            add_base_query := add_base_query || ' AND cp.id = ' || NEW.id;
            add_peer_query := add_peer_query || ' AND cp.id = ' || NEW.id;
            EXECUTE add_front || add_base_query || ' UNION ' || add_peer_query || add_back;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('call_number', 'record_entry') THEN -- these have a 'deleted' column
 
        IF OLD.deleted AND NEW.deleted THEN -- do nothing

            RETURN NEW;
 
        ELSIF NEW.deleted THEN -- remove rows
 
            IF TG_TABLE_NAME = 'call_number' THEN
                DELETE FROM asset.opac_visible_copies WHERE copy_id IN (SELECT id FROM asset.copy WHERE call_number = NEW.id);
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                DELETE FROM asset.opac_visible_copies WHERE record = NEW.id;
            END IF;
 
            RETURN NEW;
 
        ELSIF OLD.deleted THEN -- add rows
 
            IF TG_TABLE_NAME = 'call_number' THEN
                add_base_query := add_base_query || ' AND cn.id = ' || NEW.id;
                EXECUTE add_front || add_base_query || add_back;
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                add_base_query := add_base_query || ' AND cn.record = ' || NEW.id;
                add_peer_query := add_peer_query || ' AND pbcm.peer_record = ' || NEW.id;
                EXECUTE add_front || add_base_query || ' UNION ' || add_peer_query || add_back;
            END IF;
 
            RETURN NEW;
 
        END IF;
 
    END IF;

    IF TG_TABLE_NAME = 'call_number' THEN

        IF OLD.record <> NEW.record THEN
            -- call number is linked to different bib
            remove_query := remove_query || 'call_number = ' || NEW.id || ');';
            EXECUTE remove_query;
            add_base_query := add_base_query || ' AND cn.id = ' || NEW.id;
            EXECUTE add_front || add_base_query || add_back;
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
            add_base_query := add_base_query || ' AND cp.circ_lib = ' || NEW.id;
            add_peer_query := add_peer_query || ' AND cp.circ_lib = ' || NEW.id;
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            add_base_query := add_base_query || ' AND cp.location = ' || NEW.id;
            add_peer_query := add_peer_query || ' AND cp.location = ' || NEW.id;
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            add_base_query := add_base_query || ' AND cp.status = ' || NEW.id;
            add_peer_query := add_peer_query || ' AND cp.status = ' || NEW.id;
        END IF;
 
        EXECUTE add_front || add_base_query || ' UNION ' || add_peer_query || add_back;
 
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


COMMIT;
