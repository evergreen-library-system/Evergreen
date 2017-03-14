BEGIN;

SELECT evergreen.upgrade_deps_block_check('1031', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype) 
VALUES (
    'ebook_api.oneclickdigital.base_uri',
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.base_uri',
        'OneClickdigital Base URI',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.base_uri',
        'Base URI for OneClickdigital API (defaults to https://api.oneclickdigital.com/v1). Using HTTPS here is strongly encouraged.',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
);

COMMIT;

