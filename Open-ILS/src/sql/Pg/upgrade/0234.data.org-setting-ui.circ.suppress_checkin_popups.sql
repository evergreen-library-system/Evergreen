BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0234'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'ui.circ.suppress_checkin_popups',
        oils_i18n_gettext(
            'ui.circ.suppress_checkin_popups', 
            'Circ: Suppress popup-dialogs during check-in.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'ui.circ.suppress_checkin_popups', 
            'Circ: Suppress popup-dialogs during check-in.', 
            'coust', 
            'description'),
        'bool'
);

COMMIT;
