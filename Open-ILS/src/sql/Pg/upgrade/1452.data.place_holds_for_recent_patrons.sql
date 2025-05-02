BEGIN;

SELECT evergreen.upgrade_deps_block_check('1452', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
VALUES (
    'ui.staff.place_holds_for_recent_patrons',
    oils_i18n_gettext(
        'ui.staff.place_holds_for_recent_patrons',
        'Place holds for recent patrons',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.staff.place_holds_for_recent_patrons',
        'Loading a patron in the place holds interface designates them as recent. ' ||
        'Show the interface to load recent patrons when placing holds.',
        'coust',
        'description'
    ),
    'gui',
    'bool'
);

COMMIT;
