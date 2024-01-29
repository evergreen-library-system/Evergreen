BEGIN;

SELECT evergreen.upgrade_deps_block_check('1400', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.actor.stat_cat_entry', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.actor.stat_cat_entry',
        'Grid Config: admin.local.actor.stat_cat_entry',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.asset.stat_cat_entry', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.asset.stat_cat_entry',
        'Grid Config: admin.local.asset.stat_cat_entry',
        'cwst', 'label'
    )
);

COMMIT;
