-- remove unused org unit setting for self checkout interface

BEGIN;

SELECT evergreen.upgrade_deps_block_check('1010', :eg_version);

DELETE FROM actor.org_unit_setting WHERE name = 'circ.selfcheck.require_patron_password';

DELETE FROM config.org_unit_setting_type WHERE name = 'circ.selfcheck.require_patron_password';

DELETE FROM config.org_unit_setting_type_log WHERE field_name = 'circ.selfcheck.require_patron_password';

DELETE FROM permission.usr_perm_map WHERE perm IN (SELECT id FROM permission.perm_list WHERE code = 'UPDATE_ORG_UNIT_SETTING.circ.selfcheck.require_patron_password');

DELETE FROM permission.grp_perm_map WHERE perm IN (SELECT id FROM permission.perm_list WHERE code = 'UPDATE_ORG_UNIT_SETTING.circ.selfcheck.require_patron_password');

DELETE FROM permission.perm_list WHERE code = 'UPDATE_ORG_UNIT_SETTING.circ.selfcheck.require_patron_password';

COMMIT;
