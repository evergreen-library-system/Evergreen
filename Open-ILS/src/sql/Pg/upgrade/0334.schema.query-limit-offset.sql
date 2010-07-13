BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0334'); -- Scott McKellar

ALTER TABLE query.stored_query
ADD COLUMN limit_count INT;

ALTER TABLE query.stored_query
ADD COLUMN offset_count INT;

COMMIT;
