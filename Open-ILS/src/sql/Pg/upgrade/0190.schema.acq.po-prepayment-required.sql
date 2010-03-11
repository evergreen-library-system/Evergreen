BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0190'); -- Scott McKellar

ALTER TABLE acq.purchase_order
	ADD COLUMN prepayment_required BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE acq.acq_purchase_order_history
	ADD COLUMN prepayment_required BOOLEAN NOT NULL DEFAULT FALSE;

COMMIT;
