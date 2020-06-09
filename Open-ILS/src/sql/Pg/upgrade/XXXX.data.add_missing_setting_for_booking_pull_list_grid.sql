BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.booking.pull_list', 'gui', 'object',
    oils_i18n_gettext(
        'booking.pull_list',
        'Grid Config: Booking Pull List',
        'cwst', 'label')
);

COMMIT;
