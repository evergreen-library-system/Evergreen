-- Evergreen DB patch XXXX.schema.hold-current-shelf-lib.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- add the new column
ALTER TABLE action.hold_request ADD COLUMN current_shelf_lib 
    INT REFERENCES actor.org_unit DEFERRABLE INITIALLY DEFERRED;

-- set the value for current_shelf_lib on existing shelved holds
UPDATE action.hold_request ahr
    SET current_shelf_lib = pickup_lib
    FROM asset.copy acp
    WHERE 
            ahr.shelf_time IS NOT NULL 
        AND ahr.capture_time IS NOT NULL
        AND ahr.current_copy IS NOT NULL
        AND ahr.fulfillment_time IS NULL
        AND ahr.cancel_time IS NULL
        AND acp.id = ahr.current_copy
        AND acp.status = 8; -- on holds shelf

COMMIT;
