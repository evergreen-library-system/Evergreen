BEGIN;

SELECT evergreen.upgrade_deps_block_check('1327', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.orgselect.show_combined_names', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.orgselect.show_combined_names',
        'Library Selector Show Combined Names',
        'cwst', 'label'
    )
);

COMMIT;
