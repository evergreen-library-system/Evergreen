BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0134');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES 
( 'lib.courier_code',
    oils_i18n_gettext('lib.courier_code', 'Courier Code', 'coust', 'label'),
    oils_i18n_gettext('lib.courier_code', 'Courier Code for the library.  Available in transit slip templates as the %courier_code% macro.', 'coust', 'description'),
    'string')
;

COMMIT;
