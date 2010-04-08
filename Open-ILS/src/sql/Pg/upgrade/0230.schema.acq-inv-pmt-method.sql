BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0230'); -- Scott McKellar

CREATE TABLE acq.invoice_payment_method (
	code      TEXT     PRIMARY KEY,
	name      TEXT     NOT NULL
);

ALTER TABLE acq.invoice
	ADD COLUMN payment_auth TEXT;

ALTER TABLE acq.invoice
	ADD COLUMN payment_method TEXT
		REFERENCES acq.invoice_payment_method (code)
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.invoice
	ADD COLUMN note TEXT;

COMMIT;
