-- Evergreen DB patch XXXX.shelving-location-with-lassos.sql
--
-- Global flag to display shelving locations with lassos in the staff client
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.global_flag (name, enabled, label)
    VALUES (
        'staff.search.shelving_location_groups_with_lassos', TRUE,
        oils_i18n_gettext(
            'staff.search.shelving_location_groups_with_lassos',
            'Staff Catalog Search: Display shelving location groups with library groups',
            'cgf',
            'label'
        )
);

COMMIT;
