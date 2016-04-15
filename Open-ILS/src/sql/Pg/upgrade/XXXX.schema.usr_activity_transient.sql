
BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE config.usr_activity_type 
    ALTER COLUMN transient SET DEFAULT TRUE;

COMMIT;

