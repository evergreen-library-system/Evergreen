BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0475'); -- dbwells

CREATE OR REPLACE FUNCTION asset.autogenerate_placeholder_barcode ( ) RETURNS TRIGGER AS $f$
BEGIN
	IF NEW.barcode LIKE '@@%' THEN
		NEW.barcode := '@@' || NEW.id;
	END IF;
	RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER autogenerate_placeholder_barcode
	BEFORE INSERT OR UPDATE ON asset.copy
	FOR EACH ROW EXECUTE PROCEDURE asset.autogenerate_placeholder_barcode();

COMMIT;
