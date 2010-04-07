BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0229'); -- Scott McKellar

ALTER TABLE acq.invoice_item
	ADD COLUMN FUND INT
		REFERENCES acq.fund (id)
		DEFERRABLE INITIALLY DEFERRED;

COMMIT;
