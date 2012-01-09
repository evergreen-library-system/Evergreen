-- Evergreen DB patch 0664.schema.hold-current-shelf-lib.sql
--
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0664', :eg_version);

-- add the new column
ALTER TABLE action.hold_request ADD COLUMN current_shelf_lib 
    INT REFERENCES actor.org_unit DEFERRABLE INITIALLY DEFERRED;

-- set the value for current_shelf_lib on existing shelved holds
UPDATE action.hold_request
    SET current_shelf_lib = pickup_lib
    FROM asset.copy
    WHERE 
            action.hold_request.shelf_time IS NOT NULL 
        AND action.hold_request.capture_time IS NOT NULL
        AND action.hold_request.current_copy IS NOT NULL
        AND action.hold_request.fulfillment_time IS NULL
        AND action.hold_request.cancel_time IS NULL
        AND asset.copy.id = action.hold_request.current_copy
        AND asset.copy.status = 8; -- on holds shelf

COMMIT;
