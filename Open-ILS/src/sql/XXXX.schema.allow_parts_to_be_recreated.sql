BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE biblio.monograph_part DROP CONSTRAINT "record_label_unique";
CREATE UNIQUE INDEX CONCURRENTLY record_label_unique_idx ON biblio.monograph_part (record, label) WHERE deleted = FALSE;

COMMIT;
