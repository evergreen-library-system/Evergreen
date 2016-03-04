BEGIN;

SELECT evergreen.upgrade_deps_block_check('0971', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.protect_reserved_rows_from_delete() RETURNS trigger AS $protect_reserved$
BEGIN
IF OLD.id < TG_ARGV[0]::INT THEN
    RAISE EXCEPTION 'Cannot delete row with reserved ID %', OLD.id; 
END IF;
RETURN OLD;
END
$protect_reserved$
LANGUAGE plpgsql;

COMMIT;
