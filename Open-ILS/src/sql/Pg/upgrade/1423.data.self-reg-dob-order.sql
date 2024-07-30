BEGIN;

SELECT evergreen.upgrade_deps_block_check('1423', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, datatype, label, description)
VALUES (
    'opac.self_register.dob_order',
    'opac',
    'string',
    oils_i18n_gettext(
        'opac.self_register.dob_order',
        'Patron Self-Reg. Date of Birth Order',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.self_register.dob_order',
        'The order in which to present the Month, Day, and Year elements for the Date of Birth field in Patron Self-Registration. Use the letter M for Month, D for Day, and Y for Year. Examples: MDY, DMY, YMD',
        'coust',
        'description'
    )
);

INSERT INTO config.org_unit_setting_type
    (name, grp, datatype, label, description)
VALUES (
    'opac.patron.edit.au.usrname.hide',
    'opac',
    'bool',
    oils_i18n_gettext(
        'opac.patron.edit.au.usrname.hide',
        'Hide Username field in Patron Self-Reg.',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.patron.edit.au.usrname.hide',
        'Hides the Requested Username field in the Patron Self-Registration interface.',
        'coust',
        'description'
    )
);

COMMIT;
