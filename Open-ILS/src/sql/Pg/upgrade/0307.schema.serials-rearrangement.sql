BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0307'); --miker

ALTER TABLE serial.caption_and_pattern DROP COLUMN record;
ALTER TABLE serial.caption_and_pattern ADD COLUMN subscription INT NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE serial.distribution ADD COLUMN record_entry INT REFERENCES serial.record_entry (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
CREATE UNIQUE INDEX one_dist_per_sre_idx ON serial.distribution (record_entry);


COMMIT;

