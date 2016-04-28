--Upgrade Script for 2.9.3 to 2.9.4
\set eg_version '''2.9.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.9.4', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0977', :eg_version); -- Callender/Dyrcona/gmcharlt

ALTER TABLE biblio.monograph_part DROP CONSTRAINT "record_label_unique";
CREATE UNIQUE INDEX record_label_unique_idx ON biblio.monograph_part (record, label) WHERE deleted = FALSE;

COMMIT;
