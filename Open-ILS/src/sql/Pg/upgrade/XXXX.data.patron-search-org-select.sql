BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.orgselect.hopeless.wide_holds', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.orgselect.hopeless.wide_holds',
        'Default org unit for hopeless holds interface',
        'cwst', 'label'
    )
);

COMMIT;


