
BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version); 

/*
INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.catalog.results.count', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.catalog.results.count',
        'Catalog Results Page Size',
        'cwst', 'label'
    )
);
*/

eg.circ.patron.holds.prefetch

eg.grid.circ.patron.holds

holds_for_patron print template

COMMIT;
