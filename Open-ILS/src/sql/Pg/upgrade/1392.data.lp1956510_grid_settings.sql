BEGIN;

SELECT evergreen.upgrade_deps_block_check('1392', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.acq.fiscal_calendar', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.fiscal_calendar',
        'Grid Config: eg.grid.admin.acq.fiscal_calendar',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.fiscal_year', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.fiscal_year',
        'Grid Config: eg.grid.admin.acq.fiscal_year',
        'cwst', 'label'
    )
);

COMMIT;
