BEGIN;

SELECT evergreen.upgrade_deps_block_check('1216', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.orgselect.patron.search', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.orgselect.patron.search',
        'Default org unit for patron search',
        'cwst', 'label'
    )
);

COMMIT;


