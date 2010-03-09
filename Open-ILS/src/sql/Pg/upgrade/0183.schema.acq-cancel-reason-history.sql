BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0183'); -- Scott McKellar

ALTER TABLE acq.lineitem
	ADD COLUMN estimated_unit_price NUMERIC;

ALTER TABLE acq.acq_lineitem_history
	ADD COLUMN claim_interval INTERVAL;

ALTER TABLE acq.acq_lineitem_history
	ADD COLUMN cancel_reason INTEGER;

ALTER TABLE acq.acq_lineitem_history
	ADD COLUMN estimated_unit_price NUMERIC;

ALTER TABLE acq.acq_purchase_order_history
	ADD COLUMN cancel_reason INTEGER;

COMMIT;
