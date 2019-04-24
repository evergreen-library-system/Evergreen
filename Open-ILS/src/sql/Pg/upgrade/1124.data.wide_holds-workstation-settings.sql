BEGIN;

SELECT evergreen.upgrade_deps_block_check('1124', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.circ.wide_holds.shelf', 'gui', 'object',
    oils_i18n_gettext (
        'eg.grid.circ.wide_holds.shelf',
        'Grid Config: circ.wide_holds.shelf',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.catalog.wide_holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.catalog.wide_holds',
        'Grid Config: cat.catalog.wide_holds',
        'cwst', 'label'
    )
);

DELETE from config.workstation_setting_type
WHERE name = 'eg.grid.cat.catalog.holds' OR name = 'eg.grid.circ.holds.shelf';

COMMIT;
