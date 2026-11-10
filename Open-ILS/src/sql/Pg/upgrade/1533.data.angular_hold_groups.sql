BEGIN;

SELECT evergreen.upgrade_deps_block_check('1533', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.bucket.batch_hold.event_holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.event_holds',
        'Grid Config: eg.grid.cat.bucket.batch_hold.event_holds',
        'cwst', 'label'
    )
);

COMMIT;
