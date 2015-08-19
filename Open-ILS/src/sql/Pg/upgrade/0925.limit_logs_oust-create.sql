BEGIN;

SELECT evergreen.upgrade_deps_block_check('0925', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.limit_oustl() RETURNS TRIGGER AS $oustl_limit$
    BEGIN
        -- Only keeps the most recent five settings changes.
        DELETE FROM config.org_unit_setting_type_log WHERE field_name = NEW.field_name AND org = NEW.org AND date_applied NOT IN 
        (SELECT date_applied FROM config.org_unit_setting_type_log WHERE field_name = NEW.field_name AND org = NEW.org ORDER BY date_applied DESC LIMIT 4);
        
        IF (TG_OP = 'UPDATE') THEN
            RETURN NEW;
        ELSIF (TG_OP = 'INSERT') THEN
            RETURN NEW;
        END IF;
        RETURN NULL;
    END;
$oustl_limit$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS limit_logs_oust ON config.org_unit_setting_type_log;

CREATE TRIGGER limit_logs_oust
    BEFORE INSERT OR UPDATE ON config.org_unit_setting_type_log
    FOR EACH ROW EXECUTE PROCEDURE limit_oustl();

COMMIT;
