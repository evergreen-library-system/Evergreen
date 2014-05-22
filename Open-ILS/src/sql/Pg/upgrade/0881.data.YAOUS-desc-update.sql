BEGIN;

SELECT evergreen.upgrade_deps_block_check('0881', :eg_version);

UPDATE config.org_unit_setting_type
    SET description = replace(replace(description,'Original','Physical'),'"ol"','"physical_loc"')
    WHERE name = 'opac.org_unit_hiding.depth';

COMMIT;
