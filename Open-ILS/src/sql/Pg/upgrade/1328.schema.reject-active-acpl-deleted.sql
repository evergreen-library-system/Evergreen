BEGIN;

SELECT evergreen.upgrade_deps_block_check('1328', :eg_version);

CREATE OR REPLACE FUNCTION asset.check_delete_copy_location(acpl_id INTEGER)
    RETURNS VOID AS $FUNK$
BEGIN
    PERFORM TRUE FROM asset.copy WHERE location = acpl_id AND NOT deleted LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Copy location % contains active copies and cannot be deleted', acpl_id;
    END IF;
END;
$FUNK$ LANGUAGE plpgsql;

DROP RULE protect_copy_location_delete ON asset.copy_location;

CREATE RULE protect_copy_location_delete AS
    ON DELETE TO asset.copy_location DO INSTEAD (
        SELECT asset.check_delete_copy_location(OLD.id);
        UPDATE asset.copy_location SET deleted = TRUE WHERE OLD.id = asset.copy_location.id;
        UPDATE acq.lineitem_detail SET location = NULL WHERE location = OLD.id;
        DELETE FROM asset.copy_location_order WHERE location = OLD.id;
        DELETE FROM asset.copy_location_group_map WHERE location = OLD.id;
        DELETE FROM config.circ_limit_set_copy_loc_map WHERE copy_loc = OLD.id;
    );

COMMIT;

