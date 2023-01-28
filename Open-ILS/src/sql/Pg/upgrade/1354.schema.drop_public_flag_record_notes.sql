BEGIN;

SELECT evergreen.upgrade_deps_block_check('1354', :eg_version);

ALTER TABLE biblio.record_note DROP COLUMN pub;

COMMIT;
