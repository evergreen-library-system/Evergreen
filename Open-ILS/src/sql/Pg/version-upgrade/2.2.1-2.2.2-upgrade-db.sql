--Upgrade Script for 2.2.1 to 2.2.2
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.2.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0736', :eg_version);

INSERT INTO permission.perm_list (id, code, description)
    VALUES (539, 'UPDATE_ORG_UNIT_SETTING.ui.hide_copy_editor_fields', 'Allows staff to edit displayed copy editor fields');

UPDATE config.org_unit_setting_type SET update_perm = 539 WHERE name = 'ui.hide_copy_editor_fields';


COMMIT;
