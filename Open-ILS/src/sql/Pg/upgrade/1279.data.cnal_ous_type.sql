BEGIN;

SELECT evergreen.upgrade_deps_block_check('1279', :eg_version);

UPDATE config.org_unit_setting_type SET fm_class='cnal', datatype='link' WHERE name='ui.patron.default_inet_access_level';

COMMIT;

