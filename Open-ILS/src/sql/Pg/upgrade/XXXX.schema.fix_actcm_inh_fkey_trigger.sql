BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- In some cases, asset.copy_tag_copy_map might have an inh_fkey()
-- trigger that fires on delete when it's not supposed to. This
-- update drops all inh_fkey triggers on that table and recreates
-- the known good version.
DROP TRIGGER IF EXISTS inherit_asset_copy_tag_copy_map_copy_fkey ON asset.copy_tag_copy_map;
DROP TRIGGER IF EXISTS inherit_copy_tag_copy_map_copy_fkey ON asset.copy_tag_copy_map;

CREATE CONSTRAINT TRIGGER inherit_asset_copy_tag_copy_map_copy_fkey
        AFTER UPDATE OR INSERT ON asset.copy_tag_copy_map
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_tag_copy_map_copy_inh_fkey();

COMMIT;
