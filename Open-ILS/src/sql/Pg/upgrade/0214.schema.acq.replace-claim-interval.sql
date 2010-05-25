BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0214'); -- Scott McKellar

ALTER TABLE acq.acq_lineitem_history
	DROP COLUMN claim_interval;

ALTER TABLE acq.acq_lineitem_history
	ADD COLUMN claim_policy INT
		REFERENCES acq.claim_policy
		DEFERRABLE INITIALLY DEFERRED;

--SELECT acq.create_acq_lifecycle('acq', 'lineitem');

COMMIT;
