-- No transaction is required
INSERT INTO config.upgrade_log (version) VALUES ('0374'); -- dbs

-- Triggers on the vandelay.queued_*_record tables delete entries from
-- the associated vandelay.queued_*_record_attr tables based on the record's
-- ID; create an index on that column to avoid sequential scans for each
-- queued record that is deleted
CREATE INDEX queued_bib_record_attr_record_idx ON vandelay.queued_bib_record_attr (record);
CREATE INDEX queued_authority_record_attr_record_idx ON vandelay.queued_authority_record_attr (record);

-- Avoid sequential scans for queue retrieval operations by providing an
-- index on the queue column
CREATE INDEX queued_bib_record_queue_idx ON vandelay.queued_bib_record (queue);
CREATE INDEX queued_authority_record_queue_idx ON vandelay.queued_authority_record (queue);
