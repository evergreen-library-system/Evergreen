BEGIN;

SELECT evergreen.upgrade_deps_block_check('1451', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record.parts', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record.parts',
        'Grid Config: catalog.record.parts',
        'cwst', 'label'
       )
);

COMMIT;

