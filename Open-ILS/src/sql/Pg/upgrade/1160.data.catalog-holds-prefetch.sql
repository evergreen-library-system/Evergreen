BEGIN;

SELECT evergreen.upgrade_deps_block_check('1160', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'catalog.record.holds.prefetch', 'cat', 'bool',
    oils_i18n_gettext(
        'catalog.record.holds.prefetch',
        'Pre-Fetch Record Holds',
        'cwst', 'label'
    )
);

COMMIT;
