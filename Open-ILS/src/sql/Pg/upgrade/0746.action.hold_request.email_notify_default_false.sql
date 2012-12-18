BEGIN;

SELECT evergreen.upgrade_deps_block_check('0746', :eg_version);

ALTER TABLE action.hold_request ALTER COLUMN email_notify SET DEFAULT 'false';

COMMIT;
