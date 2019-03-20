BEGIN;

SELECT evergreen.upgrade_deps_block_check('1156', :eg_version);

ALTER TABLE reporter.template ALTER COLUMN description SET DEFAULT '';

COMMIT;
