BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'ui.staff.grid.density',
    'gui',
    oils_i18n_gettext('ui.staff.grid.density',
        'Grid UI density',
        'coust', 'label'),
    oils_i18n_gettext('ui.staff.grid.density',
        'Whitespace around table cells in staff UI data grids. Default is "standard".',
        'coust', 'description'),
    'string'
);

COMMIT;