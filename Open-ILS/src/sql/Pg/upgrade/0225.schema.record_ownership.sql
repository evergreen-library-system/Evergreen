
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0225');

ALTER TABLE biblio.record_entry ADD COLUMN owner INT REFERENCES actor.org_unit (id);
ALTER TABLE biblio.record_entry ADD COLUMN share_depth INT;

ALTER TABLE auditor.biblio_record_entry_history ADD COLUMN owner INT;
ALTER TABLE auditor.biblio_record_entry_history ADD COLUMN share_depth INT;

COMMIT;

