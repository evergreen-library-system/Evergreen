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
        'circ.patron_expires_soon_warning',
        'circ',
        oils_i18n_gettext(
            'circ.patron_expires_soon_warning',
            'Warn when patron account is about to expire',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.patron_expires_soon_warning',
            'Warn when patron account is about to expire. If set, the staff client displays a warning this many days before the expiry of a patron account. Value is in number of days, for example: 3 for 3 days.',
            'coust',
            'description'
        ),
        'integer'
    );

COMMIT;
