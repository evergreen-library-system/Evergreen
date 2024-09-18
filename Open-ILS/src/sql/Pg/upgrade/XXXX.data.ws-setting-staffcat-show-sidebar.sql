BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.staff.catalog.results.show_sidebar',
    'gui',
    oils_i18n_gettext('eg.staff.catalog.results.show_sidebar',
        'Staff catalog: show sidebar',
        'coust', 'label'),
    oils_i18n_gettext('eg.staff.catalog.results.show_sidebar',
        'Show the sidebar in staff catalog search results. Default is true.',
        'coust', 'description'),
    'bool'
);

COMMIT;