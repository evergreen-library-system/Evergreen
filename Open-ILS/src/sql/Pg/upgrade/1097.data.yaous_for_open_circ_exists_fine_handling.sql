BEGIN;

SELECT evergreen.upgrade_deps_block_check('1097', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES
        ('circ.copy_alerts.forgive_fines_on_lost_checkin',
         'circ',
         oils_i18n_gettext('circ.copy_alerts.forgive_fines_on_lost_checkin',
            'Forgive fines when checking out a lost item and copy alert is suppressed?',
            'coust', 'label'),
         oils_i18n_gettext('circ.copy_alerts.forgive_fines_on_lost_checkin',
            'Controls whether fines are automatically forgiven when checking out an '||
            'item that has been marked as lost, and the corresponding copy alert has been '||
            'suppressed.',
            'coust', 'description'),
        'bool');

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES
        ('circ.copy_alerts.forgive_fines_on_long_overdue_checkin',
         'circ',
         oils_i18n_gettext('circ.copy_alerts.forgive_fines_on_long_overdue_checkin',
            'Forgive fines when checking out a long-overdue item and copy alert is suppressed?',
            'coust', 'label'),
         oils_i18n_gettext('circ.copy_alerts.forgive_fines_on_lost_checkin',
            'Controls whether fines are automatically forgiven when checking out an '||
            'item that has been marked as lost, and the corresponding copy alert has been '||
            'suppressed.',
            'coust', 'description'),
        'bool');

COMMIT;
