BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0447'); -- gmc

-- undo 0077.data.holds_local_avail_and_override.sql
DELETE FROM actor.org_unit_setting WHERE name IN (
    'circ.holds.alert_if_local_avail',
    'circ.holds.deny_if_local_avail'
);
DELETE FROM config.org_unit_setting_type WHERE name IN (
    'circ.holds.alert_if_local_avail',
    'circ.holds.deny_if_local_avail'
);
DELETE FROM permission.usr_perm_map WHERE perm = (
   SELECT id FROM permission.perm_list WHERE code = 'HOLD_LOCAL_AVAIL_OVERRIDE'
);
DELETE FROM permission.grp_perm_map WHERE perm = (
   SELECT id FROM permission.perm_list WHERE code = 'HOLD_LOCAL_AVAIL_OVERRIDE'
);
DELETE FROM permission.perm_list WHERE code = 'HOLD_LOCAL_AVAIL_OVERRIDE';

COMMIT;
