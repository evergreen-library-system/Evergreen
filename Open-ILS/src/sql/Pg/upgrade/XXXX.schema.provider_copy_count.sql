
BEGIN;

ALTER TABLE acq.provider
    ADD COLUMN default_copy_count INTEGER NOT NULL DEFAULT 0;

COMMIT;
