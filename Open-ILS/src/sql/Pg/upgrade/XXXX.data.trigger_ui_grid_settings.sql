BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.triggers.atevdef', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.triggers.atevdef',
        'Grid Config: eg.grid.admin.local.triggers.atevdef',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.triggers.atenv', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.triggers.atenv',
        'Grid Config: eg.grid.admin.local.triggers.atenv',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.triggers.atevparam', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.triggers.atevparam',
        'Grid Config: eg.grid.admin.local.triggers.atevparam',
        'cwst', 'label'
    )
);

COMMIT;
