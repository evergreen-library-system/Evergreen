BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0154'); -- Scott McKellar

ALTER TABLE acq.provider
	ADD COLUMN active BOOL NOT NULL DEFAULT TRUE;

COMMIT;
