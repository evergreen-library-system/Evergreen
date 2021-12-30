BEGIN;

SELECT evergreen.upgrade_deps_block_check('1287', :eg_version);

 INSERT into config.org_unit_setting_type
 ( name, grp, label, description, datatype, fm_class ) VALUES
 ( 'lib.my_account_url', 'lib',
     oils_i18n_gettext('lib.my_account_url',
         'My Account URL (such as "https://example.com/eg/opac/login")',
         'coust', 'label'),
     oils_i18n_gettext('lib.my_account_url',
         'URL for a My Account link. Use a complete URL, such as "https://example.com/eg/opac/login".',
         'coust', 'description'),
     'string', null)
 ;

COMMIT;
