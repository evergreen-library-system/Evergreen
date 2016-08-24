
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0993', :eg_version);

ALTER TABLE config.usr_activity_type 
    ALTER COLUMN transient SET DEFAULT TRUE;

-- Utility function for removing all activity entries by activity type,
-- except for the most recent entry per user.  This is primarily useful
-- when cleaning up rows prior to setting the transient flag on an
-- activity type to true.  It allows for immediate cleanup of data (e.g.
-- for patron privacy) and lets admins control when the data is deleted,
-- which could be useful for huge activity tables.

CREATE OR REPLACE FUNCTION 
    actor.purge_usr_activity_by_type(act_type INTEGER) 
    RETURNS VOID AS $$
DECLARE
    cur_usr INTEGER;
BEGIN
    FOR cur_usr IN SELECT DISTINCT(usr) 
        FROM actor.usr_activity WHERE etype = act_type LOOP
        DELETE FROM actor.usr_activity WHERE id IN (
            SELECT id 
            FROM actor.usr_activity 
            WHERE usr = cur_usr AND etype = act_type
            ORDER BY event_time DESC OFFSET 1
        );

    END LOOP;
END $$ LANGUAGE PLPGSQL;

COMMIT;

