BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.admin.keyboard_shortcuts.disable_single',
    'gui',
    oils_i18n_gettext('eg.admin.keyboard_shortcuts.disable_single',
        'Staff Client: disable single-letter keyboard shortcuts',
        'coust', 'label'),
    oils_i18n_gettext('eg.admin.keyboard_shortcuts.disable_single',
        'Disables single-letter keyboard shortcuts if set to true. Screen reader users should set this to true to avoid interference with standard keyboard shortcuts.',
        'coust', 'description'),
    'bool'
);

COMMIT;