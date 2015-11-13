BEGIN;

SELECT evergreen.upgrade_deps_block_check('0949', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.protect_reserved_rows_from_delete() RETURNS trigger AS $protect_reserved$
BEGIN
IF OLD.id < TG_ARGV[0]::INT THEN
    RAISE EXCEPTION 'Cannot delete row with reserved ID %', OLD.id; 
END IF;
END
$protect_reserved$
LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS acq_no_deleted_reserved_cancel_reasons ON acq.cancel_reason;

CREATE TRIGGER acq_no_deleted_reserved_cancel_reasons BEFORE DELETE ON acq.cancel_reason
    FOR EACH ROW EXECUTE PROCEDURE evergreen.protect_reserved_rows_from_delete(2000);

ALTER TABLE acq.cancel_reason ENABLE TRIGGER acq_no_deleted_reserved_cancel_reasons;

COMMIT;
