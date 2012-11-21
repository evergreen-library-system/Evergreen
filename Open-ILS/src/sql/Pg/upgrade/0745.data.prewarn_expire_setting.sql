-- Evergreen DB patch 0745.data.prewarn_expire_setting.sql
--
-- Configuration setting to warn staff when an account is about to expire
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0745', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'circ.prewarn_expire_setting',
        'circ',
        oils_i18n_gettext(
            'circ.prewarn_expire_setting',
            'Pre-warning for patron expiration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.prewarn_expire_setting',
            'Pre-warning for patron expiration. This setting defines the number of days before patron expiration to display a message suggesting it is time to renew the patron account. Value is in number of days, for example: 3 for 3 days.',
            'coust',
            'description'
        ),
        'integer'
    );

COMMIT;
