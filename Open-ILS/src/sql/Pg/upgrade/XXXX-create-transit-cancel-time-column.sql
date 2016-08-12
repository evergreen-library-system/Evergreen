BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE action.transit_copy
	ADD COLUMN cancel_time TIMESTAMPTZ;

COMMIT;
