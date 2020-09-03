BEGIN;

SELECT evergreen.upgrade_deps_block_check('1220', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.holds.calculated_age_proximity', 'circ',
    oils_i18n_gettext('circ.holds.calculated_age_proximity',
        'Use calculated proximity for age-protection check',
        'coust', 'label'),
    oils_i18n_gettext('circ.holds.calculated_age_proximity',
        'When checking whether a copy is viable for a hold based on transit distance, use calculated proximity with adjustments rather than baseline Org Unit proximity.',
        'coust', 'description'),
    'bool', null);

COMMIT;

