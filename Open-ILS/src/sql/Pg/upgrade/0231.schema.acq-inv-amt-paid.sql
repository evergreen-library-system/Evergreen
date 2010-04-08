BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0231'); -- Scott McKellar

ALTER TABLE acq.invoice_item
	ADD COLUMN amount_paid NUMERIC (8,2);

ALTER TABLE acq.invoice_entry
	ADD COLUMN amount_paid NUMERIC (8,2);

COMMIT;
