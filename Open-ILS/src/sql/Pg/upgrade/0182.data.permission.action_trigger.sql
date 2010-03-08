BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0182'); -- dbs

INSERT INTO permission.perm_list (code, description) VALUES
    ('ADMIN_TRIGGER_CLEANUP', 'Allow a user to create, delete, and update trigger cleanup entries'),
    ('CREATE_TRIGGER_CLEANUP', 'Allow a user to create trigger cleanup entries'),
    ('DELETE_TRIGGER_CLEANUP', 'Allow a user to delete trigger cleanup entries'),
    ('UPDATE_TRIGGER_CLEANUP', 'Allow a user to update trigger cleanup entries'),
    ('CREATE_TRIGGER_EVENT_DEF', 'Allow a user to create trigger event definitions'),
    ('DELETE_TRIGGER_EVENT_DEF', 'Allow a user to delete trigger event definitions'),
    ('UPDATE_TRIGGER_EVENT_DEF', 'Allow a user to update trigger event definitions'),
    ('VIEW_TRIGGER_EVENT_DEF', 'Allow a user to view trigger event definitions'),
    ('ADMIN_TRIGGER_HOOK', 'Allow a user to create, update, and delete trigger hooks'),
    ('CREATE_TRIGGER_HOOK', 'Allow a user to create trigger hooks'),
    ('DELETE_TRIGGER_HOOK', 'Allow a user to delete trigger hooks'),
    ('UPDATE_TRIGGER_HOOK', 'Allow a user to update trigger hooks'),
    ('ADMIN_TRIGGER_REACTOR', 'Allow a user to create, update, and delete trigger reactors'),
    ('CREATE_TRIGGER_REACTOR', 'Allow a user to create trigger reactors'),
    ('DELETE_TRIGGER_REACTOR', 'Allow a user to delete trigger reactors'),
    ('UPDATE_TRIGGER_REACTOR', 'Allow a user to update trigger reactors'),
    ('ADMIN_TRIGGER_TEMPLATE_OUTPUT', 'Allow a user to delete trigger template output'),
    ('DELETE_TRIGGER_TEMPLATE_OUTPUT', 'Allow a user to delete trigger template output'),
    ('ADMIN_TRIGGER_VALIDATOR', 'Allow a user to create, update, and delete trigger validators'),
    ('CREATE_TRIGGER_VALIDATOR', 'Allow a user to create trigger validators'),
    ('DELETE_TRIGGER_VALIDATOR', 'Allow a user to delete trigger validators'),
    ('UPDATE_TRIGGER_VALIDATOR', 'Allow a user to update trigger validators')
;

-- Add trigger administration permissions to the Local System Administrator group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 10, id, 1, false FROM permission.perm_list
        WHERE code LIKE 'ADMIN_TRIGGER%'
            OR code LIKE 'CREATE_TRIGGER%'
            OR code LIKE 'DELETE_TRIGGER%'
            OR code LIKE 'UPDATE_TRIGGER%'
;
-- View trigger permissions are required at a consortial level for initial setup
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 10, id, 0, false FROM permission.perm_list WHERE code LIKE 'VIEW_TRIGGER%';

COMMIT;
