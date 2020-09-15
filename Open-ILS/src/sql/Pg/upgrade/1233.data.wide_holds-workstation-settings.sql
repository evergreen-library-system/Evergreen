BEGIN;

SELECT evergreen.upgrade_deps_block_check('1233', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.hopeless.wide_holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.hopeless.wide_holds',
        'Grid Config: hopeless.wide_holds',
        'cwst', 'label'
    )
);


COMMIT;
