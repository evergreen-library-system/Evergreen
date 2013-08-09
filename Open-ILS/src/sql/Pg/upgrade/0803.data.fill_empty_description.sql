BEGIN;

SELECT evergreen.upgrade_deps_block_check('0803', :eg_version);

UPDATE config.org_unit_setting_type 
SET description = oils_i18n_gettext('circ.holds.default_shelf_expire_interval',
        'The amount of time an item will be held on the shelf before the hold expires. For example: "2 weeks" or "5 days"',
        'coust', 'description')
WHERE name = 'circ.holds.default_shelf_expire_interval';

COMMIT;
