BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0378'); -- Scott McKellar

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
	'acq.fund.balance_limit.block',
	'Fund Spending Limit for Block',
	'coust',
	'label')
WHERE name = 'acq.fund.balance_limit.block';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
	'serial.prev_issuance_copy_location',
	'Serials: Previous Issuance Copy Location',
	'coust',
	'label'),
	description = oils_i18n_gettext(
	'serial.prev_issuance_copy_location',
	'When a serial issuance is received, copies (units) of the previous issuance will be automatically moved into the configured shelving location',
	'coust',
	'description')
WHERE name = 'serial.prev_issuance_copy_location';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
	'cat.default_classification_scheme',
	'Cataloging: Default Classification Scheme',
	'coust',
	'label'),
	description = oils_i18n_gettext(
	'cat.default_classification_scheme',
	'Defines the default classification scheme for new call numbers: 1 = Generic; 2 = Dewey; 3 = LC',
	'coust',
	'description')
WHERE name = 'cat.default_classification_scheme';

COMMIT;
