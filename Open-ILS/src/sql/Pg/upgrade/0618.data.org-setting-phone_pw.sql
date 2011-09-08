BEGIN;

SELECT evergreen.upgrade_deps_block_check('0618', :eg_version);

UPDATE config.org_unit_setting_type SET description = E'The Regular Expression for validation on the day_phone field in patron registration. Note: The first capture group will be used for the "last 4 digits of phone number" feature, if enabled. Ex: "[2-9]\\d{2}-\\d{3}-(\\d{4})( x\\d+)?" will ignore the extension on a NANP number.' WHERE name = 'ui.patron.edit.au.day_phone.regex';

UPDATE config.org_unit_setting_type SET description = 'The Regular Expression for validation on phone fields in patron registration. Applies to all phone fields without their own setting. NOTE: See description of the day_phone regex for important information about capture groups with it.' WHERE name = 'ui.patron.edit.phone.regex';

COMMIT;
