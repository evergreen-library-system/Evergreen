BEGIN;

SELECT evergreen.upgrade_deps_block_check('1237', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.staffcat.exclude_electronic', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.staffcat.exclude_electronic',
        'Staff Catalog "Exclude Electronic Resources" Option',
        'cwst', 'label'
    )
);

COMMIT;


