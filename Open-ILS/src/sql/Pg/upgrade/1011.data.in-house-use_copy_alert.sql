BEGIN;

SELECT evergreen.upgrade_deps_block_check('1011', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES
        ('circ.in_house_use.copy_alert',
         'circ',
         oils_i18n_gettext('circ.in_house_use.copy_alert',
             'Display copy alert for in-house-use',
             'coust', 'label'),
         oils_i18n_gettext('circ.in_house_use.copy_alert',
             'Display copy alert for in-house-use',
             'coust', 'description'),
         'bool'),
        ('circ.in_house_use.checkin_alert',
         'circ',
         oils_i18n_gettext('circ.in_house_use.checkin_alert',
             'Display copy location checkin alert for in-house-use',
             'coust', 'label'),
         oils_i18n_gettext('circ.in_house_use.checkin_alert',
             'Display copy location checkin alert for in-house-use',
             'coust', 'description'),
         'bool');

COMMIT;
