BEGIN;

-- Make this column NOT NULL.  This was the intent all along,
-- thwarted by a typo (NULL NULL instead of NOT NULL).

INSERT INTO config.upgrade_log (version) VALUES ('0404'); -- Scott McKellar

ALTER TABLE acq.provider_contact
	ALTER COLUMN name SET NOT NULL;

COMMIT;
