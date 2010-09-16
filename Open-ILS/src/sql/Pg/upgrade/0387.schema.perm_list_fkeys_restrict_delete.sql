
-- First drop the stuff we are going to (re)create.  If it fails for not existing, fine.

ALTER TABLE permission.grp_perm_map        DROP CONSTRAINT grp_perm_map_perm_fkey;
ALTER TABLE permission.usr_perm_map        DROP CONSTRAINT usr_perm_map_perm_fkey;
ALTER TABLE permission.usr_object_perm_map DROP CONSTRAINT usr_object_perm_map_perm_fkey;
ALTER TABLE config.org_unit_setting_type   DROP CONSTRAINT view_perm_fkey;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0387'); --gmc

ALTER TABLE permission.grp_perm_map ADD CONSTRAINT grp_perm_map_perm_fkey FOREIGN KEY (perm)
    REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE permission.usr_perm_map ADD CONSTRAINT usr_perm_map_perm_fkey FOREIGN KEY (perm)
    REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE permission.usr_object_perm_map ADD CONSTRAINT usr_object_perm_map_perm_fkey FOREIGN KEY (perm)
    REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.org_unit_setting_type ADD CONSTRAINT view_perm_fkey FOREIGN KEY (view_perm) REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

COMMIT;
