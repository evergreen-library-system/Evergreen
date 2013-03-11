BEGIN;

SELECT evergreen.upgrade_deps_block_check('0765', :eg_version);

ALTER TABLE acq.provider
    ADD COLUMN default_copy_count INTEGER NOT NULL DEFAULT 0;

COMMIT;
