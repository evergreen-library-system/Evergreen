BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
VALUES (
    'ui.staff.max_recent_patrons',
    oils_i18n_gettext(
        'ui.staff.max_recent_patrons',
        'Number of Retrievable Recent Patrons',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.staff.max_recent_patrons',
        'Number of most recently accessed patrons that can be re-retrieved ' ||
        'in the staff client.  A value of 0 or less disables the feature',
        'coust',
        'description'
    ),
    'circ',
    'integer'
);

COMMIT;
