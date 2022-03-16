BEGIN;

SELECT evergreen.upgrade_deps_block_check('1313', :eg_version); -- alynn26

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.bucket.batch_hold.view', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.view',
        'Grid Config: eg.grid.cat.bucket.batch_hold.view',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.batch_hold.pending', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.pending',
        'Grid Config: eg.grid.cat.bucket.batch_hold.pending',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.batch_hold.events', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.events',
        'Grid Config: eg.grid.cat.bucket.batch_hold.events',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.batch_hold.list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.list',
        'Grid Config: eg.grid.cat.bucket.batch_hold.list',
        'cwst', 'label'
    )
);

COMMIT;
