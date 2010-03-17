
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0199'); -- miker

CREATE OR REPLACE RULE protect_bib_rec_delete AS ON DELETE TO biblio.record_entry DO INSTEAD (UPDATE biblio.record_entry SET deleted = TRUE WHERE OLD.id = biblio.record_entry.id; DELETE FROM metabib.metarecord_source_map WHERE source = OLD.id);

COMMIT;
