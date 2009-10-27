BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0058'); -- miker

ALTER TABLE config.org_unit_setting_type ADD COLUMN view_perm INT REFERENCES permission.perm_list (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.org_unit_setting_type ADD COLUMN update_perm INT REFERENCES permission.perm_list (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

COMMIT;

