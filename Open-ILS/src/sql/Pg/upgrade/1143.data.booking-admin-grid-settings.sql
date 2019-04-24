BEGIN;

SELECT evergreen.upgrade_deps_block_check('1143', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.booking.resource', 'gui', 'object',
    oils_i18n_gettext (
        'eg.grid.admin.booking.resource',
        'Grid Config: admin.booking.resource',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.booking.resource_attr', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.booking.resource_attr',
        'Grid Config: admin.booking.resource_attr',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.booking.resource_attr_map', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.booking.resource_attr_map',
        'Grid Config: admin.booking.resource_attr_map',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.booking.resource_attr_value', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.booking.resource_attr_value',
        'Grid Config: admin.booking.resource_attr_value',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.booking.resource_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.booking.resource_type',
        'Grid Config: admin.booking.resource_type',
        'cwst', 'label'
    )
);

COMMIT;
