-- Evergreen DB patch YYYY.schema.acp_status_date_changed.sql
--
-- Change trigger which updates copy status_changed_time to ignore the
-- Reshelving->Available status rollover
-BEGIN;

-- FIXME: 0039.schema.acp_status_date_changed.sql defines this the first time
-- around, but along with the column itself, etc.  And it gets modified with
-- 0562.schema.copy_active_date.sql.  Not sure how to use the supercedes /
-- deprecate stuff for upgrade scripts, if it's even applicable when a given
-- upgrade script is doing so much.

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('YYYY', :eg_version);

CREATE OR REPLACE FUNCTION asset.acp_status_changed()
RETURNS TRIGGER AS $$
BEGIN
	IF NEW.status <> OLD.status AND NOT (NEW.status = 0 AND OLD.status = 7) THEN
        NEW.status_changed_time := now();
        IF NEW.active_date IS NULL AND NEW.status IN (SELECT id FROM config.copy_status WHERE copy_active = true) THEN
            NEW.active_date := now();
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMIT;
