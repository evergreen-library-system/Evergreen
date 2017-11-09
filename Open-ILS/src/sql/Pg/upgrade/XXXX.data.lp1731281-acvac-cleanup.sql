BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

DELETE FROM asset.copy_vis_attr_cache WHERE target_copy IN (SELECT id FROM asset.copy WHERE deleted);

COMMIT;
