BEGIN;

SELECT evergreen.upgrade_deps_block_check('1386', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    647, 'UPDATE_ADDED_CONTENT_URL',
    oils_i18n_gettext(647, 'Update the NoveList added-content javascript URL', 'ppl', 'description')
);

-- Note: see local.syndetics_id as precedence for not requiring view or update perms for credentials

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'staff.added_content.novelistselect.version',
    'gui',
    oils_i18n_gettext('staff.added_content.novelistselect.version',
        'Staff Client added content: NoveList Select API version',
        'coust', 'label'),
    oils_i18n_gettext('staff.added_content.novelistselect.version',
        'API version used to provide NoveList Select added content in the Staff Client',
        'coust', 'description'),
    'string'
);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'staff.added_content.novelistselect.profile',
    'gui',
    oils_i18n_gettext('staff.added_content.novelistselect.profile',
        'Staff Client added content: NoveList Select profile/user',
        'coust', 'label'),
    oils_i18n_gettext('staff.added_content.novelistselect.profile',
        'Profile/user used to provide NoveList Select added content in the Staff Client',
        'coust', 'description'),
    'string'
);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'staff.added_content.novelistselect.passwd',
    'gui',
    oils_i18n_gettext('staff.added_content.novelistselect.passwd',
        'Staff Client added content: NoveList Select key/password',
        'coust', 'label'),
    oils_i18n_gettext('staff.added_content.novelistselect.passwd',
        'Key/password used to provide NoveList Select added content in the Staff Client',
        'coust', 'description'),
    'string'
);

INSERT into config.org_unit_setting_type
    (name, datatype, grp, update_perm, label, description)
VALUES (
    'staff.added_content.novelistselect.url', 'string', 'opac', 647,
    oils_i18n_gettext(
        'staff.added_content.novelistselect.url',
        'URL Override for NoveList Select added content javascript',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'staff.added_content.novelistselect.url',
        'URL Override for NoveList Select added content javascript',
        'coust', 'description'
    )
);

COMMIT;
