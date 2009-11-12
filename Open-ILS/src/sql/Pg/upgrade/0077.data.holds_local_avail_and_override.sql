BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0077');   -- atz

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES 
        ('circ.holds.alert_if_local_avail',
         'Holds: Local available alert',
         'If local copy is available, alert the person making the hold',
         'bool'),

        ('circ.holds.deny_if_local_avail',
         'Holds: Local available block',
         'If local copy is available, deny the creation of the hold',
         'bool')
    ;

INSERT INTO permission.perm_list VALUES 
(351, 'HOLD_LOCAL_AVAIL_OVERRIDE', oils_i18n_gettext(351, 'Allow a user to place a hold despite the availability of a local copy', 'ppl', 'description'));

COMMIT;

