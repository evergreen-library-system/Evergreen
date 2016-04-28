BEGIN;

SELECT evergreen.upgrade_deps_block_check('0977', :eg_version); -- Callender/Dyrcona/gmcharlt

ALTER TABLE biblio.monograph_part DROP CONSTRAINT "record_label_unique";
CREATE UNIQUE INDEX record_label_unique_idx ON biblio.monograph_part (record, label) WHERE deleted = FALSE;

COMMIT;
