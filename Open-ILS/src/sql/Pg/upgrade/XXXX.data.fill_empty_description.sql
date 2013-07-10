BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

UPDATE config.org_unit_setting_type 
SET description = 'The amount of time an item will be held on the shelf before the hold expires. For example: "2 weeks" or "5 days"' 
WHERE name = 'circ.holds.default_shelf_expire_interval';

COMMIT;
