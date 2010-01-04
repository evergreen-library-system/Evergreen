BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0129'); -- Scott McKellar

ALTER TABLE acq.fund_transfer
ADD COLUMN funding_source_credit INTEGER NOT NULL
	REFERENCES acq.funding_source_credit(id)
	DEFERRABLE INITIALLY DEFERRED;

COMMIT;
