BEGIN;

SELECT evergreen.upgrade_deps_block_check('1487', :eg_version);

ALTER TABLE actor.usr ALTER COLUMN passwd DROP NOT NULL;
ALTER TABLE IF EXISTS auditor.actor_usr_history ALTER COLUMN passwd DROP NOT NULL;

COMMIT;

