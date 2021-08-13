BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.org_unit_setting_type
    (grp, name, datatype, label, description)
VALUES (
    'holds',
    'circ.holds.adjacent_target_while_stalling', 'bool',
    oils_i18n_gettext(
        'circ.holds.adjacent_target_while_stalling',
        'Allow adjacent copies to capture when Soft Stalling',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.holds.adjacent_target_while_stalling',
        'Allow adjacent copies at the targeted library to capture when Soft Stalling interval is set',
        'coust',
        'description'
    )
);

COMMIT;
