BEGIN;

SELECT evergreen.upgrade_deps_block_check('1508', :eg_version);

INSERT INTO config.org_unit_setting_type
(name, grp, label, description, datatype, update_perm)
VALUES
('staff.login.shib_sso.shib_path', 'sec',
 oils_i18n_gettext('staff.login.shib_sso.shib_path', 'Specific Shibboleth Application path. Default /Shibboleth.sso', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.shib_path', 'Specific Shibboleth Application path. Default /Shibboleth.sso', 'coust', 'description'),
 'string', 627)
ON CONFLICT DO NOTHING;

COMMIT;
