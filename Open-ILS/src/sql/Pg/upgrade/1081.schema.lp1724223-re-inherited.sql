BEGIN;

SELECT evergreen.upgrade_deps_block_check('1081', :eg_version); -- jboyer/gmcharlt

DROP TRIGGER IF EXISTS inherit_copy_bucket_item_target_copy_fkey ON container.copy_bucket_item;
DROP TRIGGER IF EXISTS inherit_import_item_imported_as_fkey ON vandelay.import_item;
DROP TRIGGER IF EXISTS inherit_asset_copy_note_copy_fkey ON asset.copy_note;
DROP TRIGGER IF EXISTS inherit_asset_copy_tag_copy_map_copy_fkey ON asset.copy_tag_copy_map;

CREATE CONSTRAINT TRIGGER inherit_copy_bucket_item_target_copy_fkey
  AFTER UPDATE OR INSERT ON container.copy_bucket_item
  DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.container_copy_bucket_item_target_copy_inh_fkey();
CREATE CONSTRAINT TRIGGER inherit_import_item_imported_as_fkey
  AFTER UPDATE OR INSERT ON vandelay.import_item
  DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.vandelay_import_item_imported_as_inh_fkey();
CREATE CONSTRAINT TRIGGER inherit_asset_copy_note_copy_fkey
  AFTER UPDATE OR INSERT ON asset.copy_note
  DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_note_owning_copy_inh_fkey();
CREATE CONSTRAINT TRIGGER inherit_asset_copy_tag_copy_map_copy_fkey
  AFTER UPDATE OR INSERT ON asset.copy_tag_copy_map
  DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_tag_copy_map_copy_inh_fkey();

COMMIT;

