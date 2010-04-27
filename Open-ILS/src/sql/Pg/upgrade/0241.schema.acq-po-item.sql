BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0241'); -- Scott McKellar

CREATE TABLE acq.po_item (
	id              SERIAL      PRIMARY KEY,
	purchase_order  INT         REFERENCES acq.purchase_order (id)
	                            ON UPDATE CASCADE ON DELETE SET NULL
	                            DEFERRABLE INITIALLY DEFERRED,
	fund_debit      INT         REFERENCES acq.fund_debit (id)
	                            DEFERRABLE INITIALLY DEFERRED,
	inv_item_type   TEXT        NOT NULL
	                            REFERENCES acq.invoice_item_type (code)
	                            DEFERRABLE INITIALLY DEFERRED,
	title           TEXT,
	author          TEXT,
	note            TEXT,
	estimated_cost  NUMERIC(8,2),
	fund            INT         REFERENCES acq.fund (id)
	                            DEFERRABLE INITIALLY DEFERRED
);

COMMIT;
