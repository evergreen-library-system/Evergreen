BEGIN;

SELECT evergreen.upgrade_deps_block_check('1389', :eg_version);

ALTER TABLE acq.provider ADD COLUMN buyer_san TEXT;

COMMIT;

