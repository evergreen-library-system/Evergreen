-- remove the Bypass hold capture during clear shelf process setting
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0739', :eg_version);


DELETE FROM actor.org_unit_setting WHERE name = 'circ.holds.clear_shelf.no_capture_holds';
DELETE FROM config.org_unit_setting_type_log WHERE field_name = 'circ.holds.clear_shelf.no_capture_holds';


DELETE FROM config.org_unit_setting_type WHERE name = 'circ.holds.clear_shelf.no_capture_holds';

COMMIT;
