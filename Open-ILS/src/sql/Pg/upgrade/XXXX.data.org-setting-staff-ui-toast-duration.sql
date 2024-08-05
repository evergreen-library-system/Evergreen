BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'ui.toast_duration',
    'gui',
    oils_i18n_gettext('ui.toast_duration',
        'Staff Client toast alert duration (seconds)',
        'coust', 'label'),
    oils_i18n_gettext('ui.toast_duration',
        'The number of seconds a toast alert should remain visible if not manually dismissed. Default is 10.',
        'coust', 'description'),
    'integer'
);

COMMIT;