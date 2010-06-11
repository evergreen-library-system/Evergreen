BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0308'); --miker

ALTER TABLE serial.subscription DROP CONSTRAINT subscription_record_entry_fkey;
ALTER TABLE serial.subscription ADD CONSTRAINT subscription_record_entry_fkey FOREIGN KEY (record_entry) REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED;

COMMIT;

