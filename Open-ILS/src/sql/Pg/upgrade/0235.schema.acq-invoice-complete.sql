BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0235');

ALTER TABLE acq.invoice
    ADD COLUMN complete BOOL NOT NULL DEFAULT FALSE;

COMMIT;
