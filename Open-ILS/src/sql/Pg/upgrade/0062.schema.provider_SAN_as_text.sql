BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0062');

ALTER TABLE acq.provider ALTER COLUMN san TYPE TEXT USING lpad(text(san), 7, '0');

COMMIT;

