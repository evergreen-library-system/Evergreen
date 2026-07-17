BEGIN;

SELECT evergreen.upgrade_deps_block_check('1520', :eg_version);

INSERT INTO permission.perm_list (code)
VALUES ('ADMIN_OPENAPI')
ON CONFLICT DO NOTHING;
    
UPDATE config.org_unit_setting_type
SET update_perm = (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_OPENAPI' LIMIT 1)
WHERE name IN ('REST.api.blacklist_properties','REST.api.whitelist_properties');

COMMIT;
