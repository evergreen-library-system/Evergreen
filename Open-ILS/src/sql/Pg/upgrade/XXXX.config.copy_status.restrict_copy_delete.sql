BEGIN;

ALTER TABLE config.copy_status
	  ADD COLUMN restrict_copy_delete BOOL NOT NULL DEFAULT FALSE;

UPDATE config.copy_status
SET restrict_copy_delete = TRUE
WHERE id IN (1,3,6,8);

COMMIT;
