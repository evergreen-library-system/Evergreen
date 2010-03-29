BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0220'); -- Scott McKellar

ALTER TABLE query.stored_query
	ALTER COLUMN from_clause DROP NOT NULL;

COMMIT;

