BEGIN;

SELECT evergreen.upgrade_deps_block_check('1393', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.staffcat.course_materials_selector', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.staffcat.course_materials_selector',
        'Add the "Reserves material" dropdown to refine search results',
        'cwst', 'label'
    )
);

COMMIT;
