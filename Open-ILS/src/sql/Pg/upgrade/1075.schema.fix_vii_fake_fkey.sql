BEGIN;

SELECT evergreen.upgrade_deps_block_check('1075', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.vandelay_import_item_imported_as_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN   
        IF NEW.imported_as IS NULL THEN
                RETURN NEW;
        END IF;
        PERFORM 1 FROM asset.copy WHERE id = NEW.imported_as;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, imported_as:%s$$, NEW.imported_as
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;


COMMIT;
