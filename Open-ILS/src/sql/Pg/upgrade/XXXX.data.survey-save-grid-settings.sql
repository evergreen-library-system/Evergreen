BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);


INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.config.survey', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.survey',
        'Grid Config: admin.local.config.survey',
        'cwst', 'label'
    )
);

COMMIT;