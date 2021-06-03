BEGIN;

--SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

ALTER TABLE acq.provider ADD COLUMN buyer_san TEXT;

COMMIT;

