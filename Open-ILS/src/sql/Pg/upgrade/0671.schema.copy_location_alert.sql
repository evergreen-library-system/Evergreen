BEGIN;

SELECT evergreen.upgrade_deps_block_check('0671', :eg_version);

ALTER TABLE asset.copy_location
    ADD COLUMN checkin_alert BOOL NOT NULL DEFAULT FALSE;

COMMIT;
