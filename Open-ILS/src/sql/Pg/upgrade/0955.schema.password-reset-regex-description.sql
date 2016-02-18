BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0955', :eg_version);

UPDATE config.org_unit_setting_type
SET description = 'Regular expression defining the password format.  Note: Be sure to update the update_password_msg.tt2 TPAC template with a user-friendly description of your password strength requirements.'
WHERE NAME = 'global.password_regex';

COMMIT;
