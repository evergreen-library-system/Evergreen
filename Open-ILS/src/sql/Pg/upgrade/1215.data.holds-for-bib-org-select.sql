BEGIN;

SELECT evergreen.upgrade_deps_block_check('1215', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.orgselect.cat.catalog.wide_holds', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.orgselect.cat.catalog.wide_holds',
        'Default org unit for catalog holds org unit selector',
        'cwst', 'label'
    )
);

COMMIT;


