BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0176'); -- Scott McKellar

ALTER TABLE acq.provider
	ADD COLUMN default_claim_interval INTERVAL;

ALTER TABLE acq.lineitem
	ADD COLUMN claim_interval INTERVAL;

COMMIT;
