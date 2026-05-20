--Upgrade Script for 3.15.12 to 3.15.13
\set eg_version '''3.15.13'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.15.13', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1520', :eg_version);

INSERT INTO permission.perm_list (code)
VALUES ('ADMIN_OPENAPI')
ON CONFLICT DO NOTHING;
    
UPDATE config.org_unit_setting_type
SET update_perm = (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_OPENAPI' LIMIT 1)
WHERE name IN ('REST.api.blacklist_properties','REST.api.whitelist_properties');


SELECT evergreen.upgrade_deps_block_check('1521', :eg_version);

--remove entries from settings table
DELETE FROM actor.org_unit_setting
WHERE
name='circ.holds.target_holds_by_org_unit_weight'
;

--remove entries from log table
DELETE FROM config.org_unit_setting_type_log
WHERE
field_name='circ.holds.target_holds_by_org_unit_weight'
;

--Remove unused org unit setting
DELETE FROM config.org_unit_setting_type
WHERE
name='circ.holds.target_holds_by_org_unit_weight'
;

COMMIT;
