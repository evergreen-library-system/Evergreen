
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0204'); -- miker

INSERT INTO config.internal_flag (name) VALUES ('ingest.reingest.force_on_same_marc');

COMMIT;

