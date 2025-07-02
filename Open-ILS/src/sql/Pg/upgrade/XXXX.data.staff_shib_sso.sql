BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- NOTE: Perm 627 is SSO_ADMIN
INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype, update_perm )
VALUES
('staff.login.shib_sso.enable',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.enable', 'Enable Shibboleth SSO for the Staff Client', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.enable', 'Enable Shibboleth SSO for the Staff Client', 'coust', 'description'),
 'bool', 627),
('staff.login.shib_sso.entityId',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.entityId', 'Shibboleth Staff SSO Entity ID', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.entityId', 'Which configured Entity ID to use for SSO when there is more than one available to Shibboleth', 'coust', 'description'),
 'string', 627),
('staff.login.shib_sso.logout',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.logout', 'Log out of the Staff Shibboleth IdP', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.logout', 'When logging out of Evergreen, also force a logout of the IdP behind Shibboleth', 'coust', 'description'),
 'bool', 627),
('staff.login.shib_sso.allow_native',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.allow_native', 'Allow both Shibboleth and native Staff Client authentication', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.allow_native', 'When Shibboleth SSO is enabled, also allow native Evergreen authentication', 'coust', 'description'),
 'bool', 627),
('staff.login.shib_sso.evergreen_matchpoint',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.evergreen_matchpoint', 'Evergreen Staff SSO matchpoint', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.evergreen_matchpoint',
  'Evergreen-side field to match a patron against for Shibboleth SSO. Default is usrname.  Other reasonable values would be barcode or email.',
  'coust', 'description'),
 'string', 627),
('staff.login.shib_sso.shib_matchpoint',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.shib_matchpoint', 'Shibboleth Staff SSO matchpoint', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.shib_matchpoint',
  'Shibboleth-side field to match a patron against for Shibboleth SSO. Default is uid; use eppn for Active Directory', 'coust', 'description'),
 'string', 627),
 ('staff.login.shib_sso.shib_path',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.shib_path', 'Specific Shibboleth Application path. Default /Shibboleth.sso', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.shib_path', 'Specific Shibboleth Application path. Default /Shibboleth.sso', 'coust', 'description'),
 'string', 627)
;

COMMIT;
