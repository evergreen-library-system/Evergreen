BEGIN;

SELECT evergreen.upgrade_deps_block_check('0790', :eg_version);

ALTER TABLE config.metabib_class ADD COLUMN combined BOOL NOT NULL DEFAULT FALSE;
UPDATE config.metabib_class SET combined = TRUE WHERE name = 'subject';

COMMIT;
