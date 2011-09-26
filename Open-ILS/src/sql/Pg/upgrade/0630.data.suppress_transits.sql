BEGIN;

SELECT evergreen.upgrade_deps_block_check('0630', :eg_version);

INSERT into config.org_unit_setting_type (name, grp, label, description, datatype) VALUES
( 'circ.transit.suppress_hold', 'circ',
    oils_i18n_gettext('circ.transit.suppress_hold',
        'Suppress Hold Transits Group',
        'coust', 'label'),
    oils_i18n_gettext('circ.transit.suppress_hold',
        'If set to a non-empty value, Hold Transits will be suppressed between this OU and others with the same value. If set to an empty value, transits will not be suppressed.',
        'coust', 'description'),
    'string')
,( 'circ.transit.suppress_non_hold', 'circ',
    oils_i18n_gettext('circ.transit.suppress_non_hold',
        'Suppress Non-Hold Transits Group',
        'coust', 'label'),
    oils_i18n_gettext('circ.transit.suppress_non_hold',
        'If set to a non-empty value, Non-Hold Transits will be suppressed between this OU and others with the same value. If set to an empty value, transits will not be suppressed.',
        'coust', 'description'),
    'string');

COMMIT;
