BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE serial.subscription_note
	ADD COLUMN alert BOOL NOT NULL DEFAULT FALSE;

ALTER TABLE serial.distribution_note
	ADD COLUMN alert BOOL NOT NULL DEFAULT FALSE;

ALTER TABLE serial.item_note
	ADD COLUMN alert BOOL NOT NULL DEFAULT FALSE;

COMMIT;
