BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.holds.pull_list_filters', 'gui', 'object',
    oils_i18n_gettext(
        'eg.holds.pull_list_filters',
        'Holds pull list filter values for pickup library and shelving locations.',
        'cwst', 'label'
    )
);

COMMIT;
