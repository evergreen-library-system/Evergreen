-- LP1076399: Prevent reactivated holds from canceling immediately.
-- Set the expire_time to NULL on all frozen/suspended holds.
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0747', :eg_version);

UPDATE action.hold_request
SET expire_time = NULL
WHERE frozen = 't'; 

COMMIT;
