BEGIN;

SELECT evergreen.upgrade_deps_block_check('1294', :eg_version); -- mmorgan / tlittle / JBoyer

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.container.carousel_org_unit', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.container.carousel_org_unit',
        'Grid Config: eg.grid.admin.local.container.carousel_org_unit',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.container.carousel', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.container.carousel',
        'Grid Config: eg.grid.admin.container.carousel',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.carousel_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.carousel_type',
        'Grid Config: eg.grid.admin.server.config.carousel_type',
        'cwst', 'label'
    )
);

COMMIT;
