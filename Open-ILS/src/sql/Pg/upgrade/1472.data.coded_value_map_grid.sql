BEGIN;

SELECT evergreen.upgrade_deps_block_check('1472', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.config.coded_value_map', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.config.coded_value_map',
        'Grid Config: eg.grid.admin.config.coded_value_map',
        'cwst', 'label'
    )
);

COMMIT;
