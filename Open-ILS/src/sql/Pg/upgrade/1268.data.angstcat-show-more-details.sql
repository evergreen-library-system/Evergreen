BEGIN;

SELECT evergreen.upgrade_deps_block_check('1268', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.staff.catalog.results.show_more', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.staff.catalog.results.show_more',
        'Show more details in Angular staff catalog',
        'cwst', 'label'
    )
);

COMMIT;
