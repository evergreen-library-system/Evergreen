BEGIN;

SELECT evergreen.upgrade_deps_block_check('1172', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label) 
VALUES (
    'eg.grid.admin.local.config.hold_matrix_matchpoint', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.hold_matrix_matchpoint',
        'Grid Config: admin.local.config.hold_matrix_matchpoint',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.actor.address_alert', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.actor.address_alert',
        'Grid Config: admin.local.actor.address_alert',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.config.barcode_completion', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.barcode_completion',
        'Grid Config: admin.local.config.barcode_completion',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.actor.copy_alert_suppress', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.actor.copy_alert_suppress',
        'Grid Config: admin.local.actor.copy_alert_suppress',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.asset.copy_location', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.asset.copy_location',
        'Grid Config: admin.local.asset.copy_location',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.asset.copy_tag', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.asset.copy_tag',
        'Grid Config: admin.local.asset.copy_tag',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.permission.grp_penalty_threshold', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.permission.grp_penalty_threshold',
        'Grid Config: admin.local.permission.grp_penalty_threshold',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.config.non_cataloged_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.non_cataloged_type',
        'Grid Config: admin.local.config.non_cataloged_type',
        'cwst', 'label'
    )
);

-- eg.grid.admin.local.rating.badge already exists

COMMIT;

