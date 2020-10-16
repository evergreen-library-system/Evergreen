BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, fm_class, label)
VALUES (
    'eg.orgselect.catalog.holdings', 'gui', 'link', 'aou',
    oils_i18n_gettext(
        'eg.orgselect.catalog.holdings',
        'Default org unit for catalog holdings tab',
        'cwst', 'label'
    )
);

COMMIT;


