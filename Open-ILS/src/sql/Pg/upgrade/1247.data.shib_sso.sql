BEGIN;

SELECT evergreen.upgrade_deps_block_check('1247', :eg_version);

INSERT INTO permission.perm_list (id,code,description) VALUES (627,'SSO_ADMIN','Modify patron SSO settings');

INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype, update_perm )
VALUES
('opac.login.shib_sso.enable',
 'opac',
 oils_i18n_gettext('opac.login.shib_sso.enable', 'Enable Shibboleth SSO for the OPAC', 'coust', 'label'),
 oils_i18n_gettext('opac.login.shib_sso.enable', 'Enable Shibboleth SSO for the OPAC', 'coust', 'description'),
 'bool', 627),
('opac.login.shib_sso.entityId',
 'opac',
 oils_i18n_gettext('opac.login.shib_sso.entityId', 'Shibboleth SSO Entity ID', 'coust', 'label'),
 oils_i18n_gettext('opac.login.shib_sso.entityId', 'Which configured Entity ID to use for SSO when there is more than one available to Shibboleth', 'coust', 'description'),
 'string', 627),
('opac.login.shib_sso.logout',
 'opac',
 oils_i18n_gettext('opac.login.shib_sso.logout', 'Log out of the Shibboleth IdP', 'coust', 'label'),
 oils_i18n_gettext('opac.login.shib_sso.logout', 'When logging out of Evergreen, also force a logout of the IdP behind Shibboleth', 'coust', 'description'),
 'bool', 627),
('opac.login.shib_sso.allow_native',
 'opac',
 oils_i18n_gettext('opac.login.shib_sso.allow_native', 'Allow both Shibboleth and native OPAC authentication', 'coust', 'label'),
 oils_i18n_gettext('opac.login.shib_sso.allow_native', 'When Shibboleth SSO is enabled, also allow native Evergreen authentication', 'coust', 'description'),
 'bool', 627),
('opac.login.shib_sso.evergreen_matchpoint',
 'opac',
 oils_i18n_gettext('opac.login.shib_sso.evergreen_matchpoint', 'Evergreen SSO matchpoint', 'coust', 'label'),
 oils_i18n_gettext('opac.login.shib_sso.evergreen_matchpoint',
  'Evergreen-side field to match a patron against for Shibboleth SSO. Default is usrname.  Other reasonable values would be barcode or email.',
  'coust', 'description'),
 'string', 627),
('opac.login.shib_sso.shib_matchpoint',
 'opac',
 oils_i18n_gettext('opac.login.shib_sso.shib_matchpoint', 'Shibboleth SSO matchpoint', 'coust', 'label'),
 oils_i18n_gettext('opac.login.shib_sso.shib_matchpoint',
  'Shibboleth-side field to match a patron against for Shibboleth SSO. Default is uid; use eppn for Active Directory', 'coust', 'description'),
 'string', 627)
;

COMMIT;
