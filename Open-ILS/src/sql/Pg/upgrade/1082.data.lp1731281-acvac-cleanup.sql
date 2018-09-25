BEGIN;

SELECT evergreen.upgrade_deps_block_check('1082', :eg_version); -- jboyer/gmcharlt

DELETE FROM asset.copy_vis_attr_cache WHERE target_copy IN (SELECT id FROM asset.copy WHERE deleted);

COMMIT;
