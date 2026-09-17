BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

--remove entry from settings table
DELETE FROM actor.org_unit_setting
WHERE name='circ.hold_stalling_hard';

--remove entries from log table
DELETE FROM config.org_unit_setting_type_log
WHERE field_name='circ.hold_stalling_hard';

--Remove unused org unit setting
DELETE FROM config.org_unit_setting_type
WHERE name='circ.hold_stalling_hard';

COMMIT;
