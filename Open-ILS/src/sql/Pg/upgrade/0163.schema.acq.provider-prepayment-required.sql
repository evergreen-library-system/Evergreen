BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0163'); -- Scott McKellar

ALTER TABLE acq.provider
	ADD COLUMN prepayment_required BOOLEAN NOT NULL DEFAULT FALSE;

COMMIT;
