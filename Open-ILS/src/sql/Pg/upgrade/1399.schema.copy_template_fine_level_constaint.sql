BEGIN;

SELECT evergreen.upgrade_deps_block_check('1399', :eg_version);

ALTER TABLE asset.copy_template DROP CONSTRAINT valid_fine_level;
ALTER TABLE asset.copy_template ADD CONSTRAINT valid_fine_level
      CHECK (fine_level IS NULL OR fine_level IN (1,2,3));

COMMIT;
