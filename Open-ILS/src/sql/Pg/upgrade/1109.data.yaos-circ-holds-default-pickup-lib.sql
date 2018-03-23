BEGIN;

SELECT evergreen.upgrade_deps_block_check('1109', :eg_version);

INSERT into config.org_unit_setting_type (name, label, grp, description, datatype)
values ('circ.staff_placed_holds_fallback_to_ws_ou','Workstation OU fallback for staff-placed holds',
        'circ', 'For staff-placed holds, in the absence of a patron preferred pickup location, fall back to using the staff workstation OU (rather than patron home OU)', 'bool');

COMMIT;

