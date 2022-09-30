BEGIN;

SELECT evergreen.upgrade_deps_block_check('1331', :eg_version);

INSERT into config.org_unit_setting_type
    (name, datatype, grp, label, description)
VALUES (
    'ui.staff.traditional_catalog.enabled', 'bool', 'gui',
    oils_i18n_gettext(
        'ui.staff.traditional_catalog.enabled',
        'GUI: Enable Traditional Staff Catalog',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.staff.traditional_catalog.enabled',
        'Display an entry point in the browser client for the ' ||
        'traditional staff catalog.',
        'coust', 'description'
    )
);

COMMIT;


