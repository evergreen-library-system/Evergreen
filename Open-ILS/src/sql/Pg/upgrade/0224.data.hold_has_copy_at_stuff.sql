BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0224');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.holds.hold_has_copy_at.alert',
        oils_i18n_gettext('circ.holds.hold_has_copy_at.alert', 'Holds: Has Local Copy Alert', 'coust', 'label'),
        oils_i18n_gettext('circ.holds.hold_has_copy_at.alert', 'If there is an available copy at the requesting library that could fulfill a hold during hold placement time, alert the patron', 'coust', 'description'),
        'bool'
    ),(
        'circ.holds.hold_has_copy_at.block',
        oils_i18n_gettext('circ.holds.hold_has_copy_at.block', 'Holds: Has Local Copy Block', 'coust', 'label'),
        oils_i18n_gettext('circ.holds.hold_has_copy_at.block', 'If there is an available copy at the requesting library that could fulfill a hold during hold placement time, do not allow the hold to be placed', 'coust', 'description'),
        'bool'
    );

INSERT INTO permission.perm_list (id, code, description)
    VALUES (
        390, 
        'OVERRIDE_HOLD_HAS_LOCAL_COPY',
        oils_i18n_gettext( 390, 'Allow a user to override the circ.holds.hold_has_copy_at.block setting', 'ppl', 'description' )
    );

COMMIT;

