BEGIN;

SELECT evergreen.upgrade_deps_block_check('1027', :eg_version);

INSERT INTO config.settings_group (name, label)
    VALUES ('ebook_api', 'Ebook API Integration');

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype) 
VALUES (
    'ebook_api.oneclickdigital.library_id',
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.library_id',
        'OneClickdigital Library ID',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.library_id',
        'Identifier assigned to this library by OneClickdigital',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.oneclickdigital.basic_token',
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.basic_token',
        'OneClickdigital Basic Token',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.basic_token',
        'Basic token for client authentication with OneClickdigital API (supplied by OneClickdigital)',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
);

COMMIT;

