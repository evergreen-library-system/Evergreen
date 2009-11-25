BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0091');

-- add some consistency to the name of an old selfcheck setting
UPDATE actor.org_unit_setting 
    SET name = 'circ.selfcheck.alert.popup' 
    WHERE name = 'circ.selfcheck.alert_on_checkout_event';

UPDATE config.org_unit_setting_type 
    SET name = 'circ.selfcheck.alert.popup' 
    WHERE name = 'circ.selfcheck.alert_on_checkout_event';

-- add the sound setting
INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES ( 
        'circ.selfcheck.alert.sound',
        oils_i18n_gettext('circ.selfcheck.alert.sound', 'Selfcheck: Audio Alerts', 'coust', 'label'),
        oils_i18n_gettext('circ.selfcheck.alert.sound', 'Use audio alerts for selfcheck events', 'coust', 'description'),
        'bool'
    );

COMMIT;
