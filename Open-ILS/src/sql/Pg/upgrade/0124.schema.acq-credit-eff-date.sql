BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0124'); -- Scott McKellar

ALTER TABLE acq.funding_source_credit
ADD COLUMN effective_date TIMESTAMPTZ NOT NULL DEFAULT now();

COMMIT;
