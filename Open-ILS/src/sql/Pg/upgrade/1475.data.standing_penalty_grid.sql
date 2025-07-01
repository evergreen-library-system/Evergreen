BEGIN;

SELECT evergreen.upgrade_deps_block_check('1475', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.config.standing_penalty', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.standing_penalty',
        'Grid Config: admin.local.config.standing_penalty',
        'cwst', 'label'
    )
);

COMMIT;
