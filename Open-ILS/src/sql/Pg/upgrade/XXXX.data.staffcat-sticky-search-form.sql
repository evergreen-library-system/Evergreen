BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.catalog.search.form.open', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.catalog.search.form.open',
        'Catalog Search Form Visibility Sticky Setting',
        'cwst', 'label'
    )
);

COMMIT;
