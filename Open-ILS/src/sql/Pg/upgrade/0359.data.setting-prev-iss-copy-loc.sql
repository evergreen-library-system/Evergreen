BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0359'); -- Scott McKellar

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class )
VALUES (
    'serial.prev_issuance_copy_location',
    oils_i18n_gettext('setting.name', 'Serials: Previous Issuance Copy Location',
		'coust', 'label'),
    oils_i18n_gettext('setting.name', 'When a serial issuance is received, copies (units) of the  previous issuance will be automatically moved into the configured shelving location',
		'coust', 'descripton'),
	'link',
    'acpl'
);

COMMIT;
