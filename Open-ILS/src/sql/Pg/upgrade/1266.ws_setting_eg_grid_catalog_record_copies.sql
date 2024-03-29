BEGIN;

SELECT evergreen.upgrade_deps_block_check('1266', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record.copies', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record.copies',
        'Grid Config: eg.grid.catalog.record.copies',
        'cwst', 'label')
    );

COMMIT;
