BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0116'); -- Scott McKellar

ALTER TABLE acq.funding_source_credit
ADD COLUMN deadline_date TIMESTAMPTZ;

COMMIT;
