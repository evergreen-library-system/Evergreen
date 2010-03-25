BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0211'); -- Scott McKellar

ALTER TABLE acq.lineitem
	DROP COLUMN claim_interval CASCADE;

ALTER TABLE acq.lineitem
	ADD COLUMN claim_policy INT
		REFERENCES acq.claim_policy
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.provider
	DROP COLUMN default_claim_interval;

ALTER TABLE acq.provider
	ADD COLUMN default_claim_policy INT
		REFERENCES acq.claim_policy
		DEFERRABLE INITIALLY DEFERRED;

COMMIT;
