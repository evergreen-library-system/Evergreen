-- Evergreen DB patch 0718.data.add-to-permanent-bookbag.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0718', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'opac.patron.temporary_list_warn',
        'opac',
        oils_i18n_gettext(
            'opac.patron.temporary_list_warn',
            'Warn patrons when adding to a temporary book list',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'opac.patron.temporary_list_warn',
            'Present a warning dialog to the patron when a patron adds a book to a temporary book bag.',
            'coust',
            'description'
        ),
        'bool'
    );

INSERT INTO config.usr_setting_type
    (name,grp,opac_visible,label,description,datatype)
VALUES (
    'opac.temporary_list_no_warn',
    'opac',
    TRUE,
    oils_i18n_gettext(
        'opac.temporary_list_no_warn',
        'Opt out of warning when adding a book to a temporary book list',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.temporary_list_no_warn',
        'Opt out of warning when adding a book to a temporary book list',
        'cust',
        'description'
    ),
    'bool'
);

INSERT INTO config.usr_setting_type
    (name,grp,opac_visible,label,description,datatype)
VALUES (
    'opac.default_list',
    'opac',
    FALSE,
    oils_i18n_gettext(
        'opac.default_list',
        'Default list to use when adding to a bookbag',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.default_list',
        'Default list to use when adding to a bookbag',
        'cust',
        'description'
    ),
    'integer'
);

COMMIT;
