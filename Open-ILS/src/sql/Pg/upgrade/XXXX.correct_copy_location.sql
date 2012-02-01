CREATE OR REPLACE FUNCTION asset.acp_location_fixer()
RETURNS TRIGGER AS $$
DECLARE
    new_copy_location INT;
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF NEW.location = OLD.location AND NEW.call_number = OLD.call_number THEN
            RETURN NEW;
        END IF;
    END IF;
    SELECT INTO new_copy_location acpl.id FROM asset.copy_location acpl JOIN actor.org_unit_ancestors_distance((SELECT owning_lib FROM asset.call_number WHERE id = NEW.call_number)) aouad ON acpl.owning_lib = aouad.id WHERE name = (SELECT name FROM asset.copy_location WHERE id = NEW.location) ORDER BY distance LIMIT 1;
    IF new_copy_location IS NOT NULL THEN
        NEW.location = new_copy_location;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acp_location_fixer_trig
    BEFORE INSERT OR UPDATE ON asset.copy
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_location_fixer();

