BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0257'); -- Scott McKellar

-- In the unlikely event that this table already has rows in it, it will
-- be necessary to add the column as nullable, populate it in the existing
-- rows, and then add the NOT NULL constraint.

ALTER TABLE query.bind_variable
	ADD COLUMN label TEXT NOT NULL;

COMMIT;
