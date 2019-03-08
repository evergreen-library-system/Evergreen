BEGIN;

SELECT evergreen.upgrade_deps_block_check('1155', :eg_version);

ALTER TABLE reporter.template ALTER COLUMN description SET DEFAULT '';

COMMIT;
