BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0236');

ALTER TABLE auditor.acq_invoice_history
    ADD COLUMN complete BOOL NOT NULL DEFAULT FALSE;

COMMIT;
