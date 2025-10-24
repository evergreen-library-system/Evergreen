BEGIN;

SELECT evergreen.upgrade_deps_block_check('1493', :eg_version);
ALTER TABLE actor.org_lasso ADD COLUMN IF NOT EXISTS opac_visible BOOL NOT NULL DEFAULT TRUE;

COMMIT;
