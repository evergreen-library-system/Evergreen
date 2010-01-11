BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0132'); -- Scott McKellar

ALTER TABLE acq.fund
	ADD COLUMN propagate BOOLEAN NOT NULL DEFAULT TRUE;

-- A fund can't roll over if it doesn't propagate from one year to the next

ALTER TABLE acq.fund
	ADD CONSTRAINT acq_fund_rollover_implies_propagate CHECK
	( propagate OR NOT rollover );

COMMIT;
