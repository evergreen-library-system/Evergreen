BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0362'); -- phasefx

ALTER TABLE auditor.acq_invoice_item_history ADD COLUMN target BIGINT;
ALTER TABLE auditor.asset_copy_history ADD COLUMN cost NUMERIC(8,2);

-- now what about the auditor.*_lifecycle views??

COMMIT;

