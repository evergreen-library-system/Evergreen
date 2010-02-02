BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0146'); -- Scott McKellar

ALTER TABLE acq.fund
	ADD COLUMN active BOOL NOT NULL DEFAULT TRUE;

COMMIT;
