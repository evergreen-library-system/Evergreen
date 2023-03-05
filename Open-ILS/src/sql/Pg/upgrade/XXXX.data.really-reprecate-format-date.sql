BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version); -- JBoyer

-- If these settings have not been marked Deprecated go ahead and do so now
UPDATE config.org_unit_setting_type SET label = 'Deprecated: ' || label WHERE name IN ('format.date', 'format.time') AND NOT label ILIKE 'deprecated: %';

COMMIT;
