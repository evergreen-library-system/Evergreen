BEGIN;

SELECT evergreen.upgrade_deps_block_check('1061', :eg_version);

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
        'in the staff client.  A value of 0 or less disables the feature. Defaults to 1.',
        'coust',
        'description'
    ),
    'circ',
    'integer'
);

COMMIT;
