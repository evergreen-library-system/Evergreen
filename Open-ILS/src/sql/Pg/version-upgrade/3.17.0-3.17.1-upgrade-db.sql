--Upgrade Script for 3.17.0 to 3.17.1
\set eg_version '''3.17.1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.17.1', :eg_version);

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
