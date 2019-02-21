BEGIN;

SELECT evergreen.upgrade_deps_block_check('1152', :eg_version);

INSERT into config.org_unit_setting_type 
    (name, datatype, grp, label, description)
VALUES ( 
    'ui.staff.angular_catalog.enabled', 'bool', 'gui',
    oils_i18n_gettext(
        'ui.staff.angular_catalog.enabled',
        'GUI: Enable Experimental Angular Staff Catalog',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.staff.angular_catalog.enabled',
        'Display an entry point in the browser client for the ' ||
        'experimental Angular staff catalog.',
        'coust', 'description'
    )
);

COMMIT;

