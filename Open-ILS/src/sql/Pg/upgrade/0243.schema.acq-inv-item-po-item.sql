BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0243'); -- Scott McKellar

ALTER TABLE acq.invoice_item
	ADD COLUMN po_item INT REFERENCES acq.po_item (id)
	                       DEFERRABLE INITIALLY DEFERRED;

COMMIT;
