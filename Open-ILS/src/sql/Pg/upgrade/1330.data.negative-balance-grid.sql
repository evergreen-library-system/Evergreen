
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1330', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.negative_balances', 'gui', 'object', 
    oils_i18n_gettext(
        'eg.grid.admin.local.negative_balances',
        'Patrons With Negative Balances Grid Settings',
        'cwst', 'label'
    )
), (
    'eg.orgselect.admin.local.negative_balances', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.orgselect.admin.local.negative_balances',
        'Default org unit for patron negative balances interface',
        'cwst', 'label'
    )
);

COMMIT;
