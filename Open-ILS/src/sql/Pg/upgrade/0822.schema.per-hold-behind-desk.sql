BEGIN;

SELECT evergreen.upgrade_deps_block_check('0822', :eg_version);

ALTER TABLE action.hold_request 
    ADD COLUMN behind_desk BOOLEAN NOT NULL DEFAULT FALSE;

-- The value on the hold is the new arbiter of whether a 
-- hold should be held behind the desk and reported as such
-- Update existing holds that would in the current regime
-- be considered behind-the-desk holds to use the new column

UPDATE action.hold_request ahr
    SET behind_desk = TRUE
    FROM actor.usr_setting aus
    WHERE 
        ahr.cancel_time IS NULL AND
        ahr.fulfillment_time IS NULL AND
        aus.usr = ahr.usr AND
        aus.name = 'circ.holds_behind_desk' AND
        aus.value = 'true' AND
        EXISTS (
            SELECT 1 
            FROM actor.org_unit_ancestor_setting(
                'circ.holds.behind_desk_pickup_supported', 
                ahr.pickup_lib
            ) 
            WHERE value = 'true'
        );

COMMIT;
