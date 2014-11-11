BEGIN;

SELECT evergreen.upgrade_deps_block_check('0896', :eg_version);

CREATE OR REPLACE FUNCTION asset.acp_location_fixer()
RETURNS TRIGGER AS $$
DECLARE
    new_copy_location INT;
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF NEW.location = OLD.location AND NEW.call_number = OLD.call_number AND NEW.circ_lib = OLD.circ_lib THEN
            RETURN NEW;
        END IF;
    END IF;
    SELECT INTO new_copy_location acpl.id FROM asset.copy_location acpl JOIN actor.org_unit_ancestors_distance((SELECT owning_lib FROM asset.call_number WHERE id = NEW.call_number)) aouad ON acpl.owning_lib = aouad.id WHERE name = (SELECT name FROM asset.copy_location WHERE id = NEW.location) ORDER BY distance LIMIT 1;
    IF new_copy_location IS NULL THEN
        SELECT INTO new_copy_location acpl.id FROM asset.copy_location acpl JOIN actor.org_unit_ancestors_distance(NEW.circ_lib) aouad ON acpl.owning_lib = aouad.id WHERE name = (SELECT name FROM asset.copy_location WHERE id = NEW.location) ORDER BY distance LIMIT 1;
    END IF;
    IF new_copy_location IS NOT NULL THEN
        NEW.location = new_copy_location;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS acp_location_fixer_trig ON asset.copy;

CREATE TRIGGER acp_location_fixer_trig
    BEFORE INSERT OR UPDATE OF location, call_number, circ_lib ON asset.copy
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_location_fixer();

COMMIT;
