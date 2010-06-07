BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0295'); -- gmcharlt

CREATE OR REPLACE FUNCTION biblio.check_marcxml_well_formed () RETURNS TRIGGER AS $func$
BEGIN

    IF xml_is_well_formed(NEW.marc) THEN
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Attempted to % MARCXML that is not well formed', TG_OP;
    END IF;
    
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER a_marcxml_is_well_formed BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.check_marcxml_well_formed();

CREATE TRIGGER a_marcxml_is_well_formed BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.check_marcxml_well_formed();

COMMIT;
