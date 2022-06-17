BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

ALTER TABLE biblio.record_note DROP COLUMN pub;

COMMIT;
