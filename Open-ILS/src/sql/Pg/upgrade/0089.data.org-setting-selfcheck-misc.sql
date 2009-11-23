BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0089');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES ( 
        'circ.selfcheck.workstation_required',
        oils_i18n_gettext('circ.selfcheck.workstation_required', 'Selfcheck: Workstation Required', 'coust', 'label'),
        oils_i18n_gettext('circ.selfcheck.workstation_required', 'All selfcheck stations must use a workstation', 'coust', 'description'),
        'bool'
    ), (
        'circ.selfcheck.patron_password_required',
        oils_i18n_gettext('circ.selfcheck.patron_password_required', 'Selfcheck: Require Patron Password', 'coust', 'label'),
        oils_i18n_gettext('circ.selfcheck.patron_password_required', 'Patron must log in with barcode and password at selfcheck station', 'coust', 'description'),
        'bool'
    );

COMMIT;
