BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0131'); -- dbs

CREATE RULE protect_mfhd_delete AS ON DELETE TO serial.record_entry DO INSTEAD UPDATE serial.record_entry SET deleted = true WHERE old.id = serial.record_entry.id;

COMMIT;
