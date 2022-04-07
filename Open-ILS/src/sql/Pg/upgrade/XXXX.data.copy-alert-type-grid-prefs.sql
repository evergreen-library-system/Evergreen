BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.config.copy_alert_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.copy_alert_type',
        'Grid Config: eg.grid.admin.local.config.copy_alert_type',
        'cwst', 'label'
    )
);

COMMIT;

