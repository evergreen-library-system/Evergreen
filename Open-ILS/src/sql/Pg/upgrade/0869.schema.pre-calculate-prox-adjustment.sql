BEGIN;

SELECT evergreen.upgrade_deps_block_check('0869', :eg_version);

CREATE OR REPLACE FUNCTION action.hold_copy_calculated_proximity_update () RETURNS TRIGGER AS $f$
BEGIN
    NEW.proximity := action.hold_copy_calculated_proximity(NEW.hold,NEW.target_copy);
    RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER hold_copy_proximity_update_tgr BEFORE INSERT OR UPDATE ON action.hold_copy_map FOR EACH ROW EXECUTE PROCEDURE action.hold_copy_calculated_proximity_update ();

-- Now, cause the update we need in a HOT-friendly manner (http://pgsql.tapoueh.org/site/html/misc/hot.html)
UPDATE action.hold_copy_map SET proximity = proximity WHERE proximity IS NULL;

COMMIT;

