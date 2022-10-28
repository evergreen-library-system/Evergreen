BEGIN;

SELECT evergreen.upgrade_deps_block_check('1352', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.cash_reports.desk_payments', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.cash_reports.desk_payments',
        'Grid Config: admin.local.cash_reports.desk_payments',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.cash_reports.user_payments', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.cash_reports.user_payments',
        'Grid Config: admin.local.cash_reports.user_payments',
        'cwst', 'label'
    )
);

COMMIT;
