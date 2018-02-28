BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

INSERT into config.org_unit_setting_type (name, label, grp, description, datatype)
values ('circ.staff_placed_holds_honor_patron_prefs_first','Honor the patron-preferred Pickup Library as default for staff-placed holds.',
        'circ', 'Honor the patron-preferred Pickup Library as the default for staff-placed holds.', 'bool');

INSERT into config.org_unit_setting_type (name, label, grp, description, datatype)
values ('circ.staff_placed_holds_staff_ws_ou_override','During Staff-placed holds, use the patron-preferred location or their home OU instead of the Staff User Workstation Org. unit as default pickup location.',
    'circ', 'During staff-placed holds, use the patron-preferred location or their home OU instead of the Staff User Workstation Org. unit as default pickup location.', 'bool');

COMMIT;

