BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);


INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.config.search_filter_group', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.search_filter_group',
        'Grid Config: admin.local.config.search_filter_group',
        'cwst', 'label'
    )
);

COMMIT;