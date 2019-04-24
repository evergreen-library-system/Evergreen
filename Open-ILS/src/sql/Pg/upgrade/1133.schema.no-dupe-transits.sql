
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1133', :eg_version);

\qecho Applying a unique constraint to action.transit_copy.  This will
\qecho only effect newly created transits.  Admins are encouraged to manually 
\qecho remove any existing duplicate transits by applying values for cancel_time
\qecho or dest_recv_time, or by deleting the offending transits. Below is a
\qecho query to locate duplicate transits.  Note dupes may exist accross
\qecho parent (action.transit_copy) and child tables (action.hold_transit_copy,
\qecho action.reservation_transit_copy)
\qecho 
\qecho    WITH dupe_transits AS (
\qecho        SELECT COUNT(*), target_copy FROM action.transit_copy
\qecho        WHERE dest_recv_time IS NULL AND cancel_time IS NULL
\qecho        GROUP BY 2 HAVING COUNT(*) > 1
\qecho    ) SELECT atc.* 
\qecho        FROM dupe_transits
\qecho        JOIN action.transit_copy atc USING (target_copy)
\qecho        WHERE dest_recv_time IS NULL AND cancel_time IS NULL;
\qecho

/* 
Unique indexes are not inherited by child tables, so they will not prevent
duplicate inserts on action.transit_copy and action.hold_transit_copy,
for example.  Use check constraints instead to enforce unique-per-copy
transits accross all transit types.
*/

-- Create an index for speedy check constraint lookups.
CREATE INDEX active_transit_for_copy 
    ON action.transit_copy (target_copy)
    WHERE dest_recv_time IS NULL AND cancel_time IS NULL;

-- Check for duplicate transits across all transit types
CREATE OR REPLACE FUNCTION action.copy_transit_is_unique() 
    RETURNS TRIGGER AS $func$
BEGIN
    PERFORM * FROM action.transit_copy 
        WHERE target_copy = NEW.target_copy 
              AND dest_recv_time IS NULL 
              AND cancel_time IS NULL;
    IF FOUND THEN
        RAISE EXCEPTION 'Copy id=% is already in transit', NEW.target_copy;
    END IF;
    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL STABLE;

-- Apply constraint to all transit tables
CREATE CONSTRAINT TRIGGER transit_copy_is_unique_check
    AFTER INSERT ON action.transit_copy
    FOR EACH ROW EXECUTE PROCEDURE action.copy_transit_is_unique();

CREATE CONSTRAINT TRIGGER hold_transit_copy_is_unique_check
    AFTER INSERT ON action.hold_transit_copy
    FOR EACH ROW EXECUTE PROCEDURE action.copy_transit_is_unique();

CREATE CONSTRAINT TRIGGER reservation_transit_copy_is_unique_check
    AFTER INSERT ON action.reservation_transit_copy
    FOR EACH ROW EXECUTE PROCEDURE action.copy_transit_is_unique();

/*
-- UNDO
DROP TRIGGER transit_copy_is_unique_check ON action.transit_copy;
DROP TRIGGER hold_transit_copy_is_unique_check ON action.hold_transit_copy;
DROP TRIGGER reservation_transit_copy_is_unique_check ON action.reservation_transit_copy;
DROP INDEX action.active_transit_for_copy;
*/

COMMIT;

