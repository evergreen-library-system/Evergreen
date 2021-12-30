BEGIN;

SELECT evergreen.upgrade_deps_block_check('1276', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.acq.fund.fund_debit', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.fund.fund_debit',
        'Grid Config: eg.grid.acq.fund.fund_debit',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.fund.fund_transfer', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.fund.fund_transfer',
        'Grid Config: eg.grid.acq.fund.fund_transfer',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.fund.fund_allocation', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.fund.fund_allocation',
        'Grid Config: eg.grid.acq.fund.fund_allocation',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.fund', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.fund',
        'Grid Config: eg.grid.admin.acq.fund',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.funding_source', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.funding_source',
        'Grid Config: eg.grid.admin.acq.funding_source',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.funding_source.fund_allocation', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.funding_source.fund_allocation',
        'Grid Config: eg.grid.acq.funding_source.fund_allocation',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.funding_source.credit', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.funding_source.credit',
        'Grid Config: eg.grid.acq.funding_source.credit',
        'cwst', 'label'
    )
);

COMMIT;
