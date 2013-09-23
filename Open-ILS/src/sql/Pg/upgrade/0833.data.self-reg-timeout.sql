BEGIN;

SELECT evergreen.upgrade_deps_block_check('0833', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, datatype, label, description)
VALUES (
    'opac.self_register.timeout',
    'opac',
    'integer',
    oils_i18n_gettext(
        'opac.self_register.timeout',
        'Patron Self-Reg. Display Timeout',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.self_register.timeout',
        'Number of seconds to wait before reloading the patron self-'||
        'registration interface to clear sensitive data',
        'coust',
        'description'
    )
);

COMMIT;
