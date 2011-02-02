BEGIN;

INSERT INTO config.upgrade_log(version) VALUES ('0481'); -- dbs

-- We defined the same trigger on the parent table asset.copy
-- but we need to define it on child tables explicitly as well
CREATE TRIGGER autogenerate_placeholder_barcode
   BEFORE INSERT OR UPDATE ON serial.unit 
   FOR EACH ROW EXECUTE PROCEDURE asset.autogenerate_placeholder_barcode()
;

COMMIT;
