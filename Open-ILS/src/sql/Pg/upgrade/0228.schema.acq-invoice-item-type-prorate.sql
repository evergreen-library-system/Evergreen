BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0228'); -- Scott McKellar

ALTER TABLE acq.invoice_item_type
	ADD COLUMN prorate BOOL NOT NULL DEFAULT FALSE;

COMMIT;
