
-- First drop the stuff we are going to (re)create.  If it fails for not existing, fine.
-- Some constraints might have different names, so we try all of them.
ALTER TABLE permission.grp_perm_map        DROP CONSTRAINT grp_perm_map_perm_fkey;
ALTER TABLE permission.usr_perm_map        DROP CONSTRAINT usr_perm_map_perm_fkey;
ALTER TABLE permission.usr_object_perm_map DROP CONSTRAINT usr_object_perm_map_perm_fkey;

ALTER TABLE config.org_unit_setting_type   DROP CONSTRAINT view_perm_fkey;
ALTER TABLE config.org_unit_setting_type   DROP CONSTRAINT update_perm_fkey;
ALTER TABLE config.org_unit_setting_type   DROP CONSTRAINT org_unit_setting_type_view_perm_fkey;    -- alternate name
ALTER TABLE config.org_unit_setting_type   DROP CONSTRAINT org_unit_setting_type_update_perm_fkey;  -- alternate name


BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0385'); --gmc

ALTER TABLE permission.grp_perm_map ADD CONSTRAINT grp_perm_map_perm_fkey FOREIGN KEY (perm)
    REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE permission.usr_perm_map ADD CONSTRAINT usr_perm_map_perm_fkey FOREIGN KEY (perm)
    REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE permission.usr_object_perm_map ADD CONSTRAINT usr_object_perm_map_perm_fkey FOREIGN KEY (perm)
    REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.org_unit_setting_type ADD CONSTRAINT view_perm_fkey   FOREIGN KEY (view_perm  ) REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.org_unit_setting_type ADD CONSTRAINT update_perm_fkey FOREIGN KEY (update_perm) REFERENCES permission.perm_list (id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;

COMMIT;
