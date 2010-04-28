BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0244'); -- Scott McKellar

ALTER TABLE auditor.acq_invoice_item_history
	ADD COLUMN po_item INT;

COMMIT;
