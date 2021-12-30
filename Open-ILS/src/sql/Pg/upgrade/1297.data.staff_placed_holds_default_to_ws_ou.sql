BEGIN;

SELECT evergreen.upgrade_deps_block_check('1297', :eg_version);

INSERT INTO config.org_unit_setting_type (
    name, grp, label, description, datatype
) VALUES (
    'circ.staff_placed_holds_default_to_ws_ou',
    'circ',
    oils_i18n_gettext(
        'circ.staff_placed_holds_default_to_ws_ou',
        'Workstation OU is the default for staff-placed holds',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.staff_placed_holds_default_to_ws_ou',
        'For staff-placed holds, regardless of the patron preferred pickup location, the staff workstation OU is the default pickup location',
        'coust',
        'description'
    ),
    'bool'
);

COMMIT;
