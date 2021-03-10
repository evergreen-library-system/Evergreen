BEGIN;

SELECT evergreen.upgrade_deps_block_check('1251', :eg_version);

INSERT INTO config.org_unit_setting_type
    (grp, name, datatype, label, description)
VALUES (
    'circ',
    'circ.renew.expired_patron_allow', 'bool',
    oils_i18n_gettext(
        'circ.renew.expired_patron_allow',
        'Allow renewal request if renewal recipient privileges have expired',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.renew.expired_patron_allow',
        'If enabled, users within the org unit who are expired may still renew items.',
        'coust',
        'description'
    )
);

COMMIT;
