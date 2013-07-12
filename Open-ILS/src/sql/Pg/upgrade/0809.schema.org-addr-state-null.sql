BEGIN;

SELECT evergreen.upgrade_deps_block_check('0809', :eg_version);

ALTER TABLE actor.org_address ALTER COLUMN state DROP NOT NULL;

COMMIT;

