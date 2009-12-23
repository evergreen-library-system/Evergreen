BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0123'); -- Scott McKellar

ALTER TABLE acq.fund
ADD COLUMN rollover BOOL NOT NULL DEFAULT FALSE;

COMMIT;
