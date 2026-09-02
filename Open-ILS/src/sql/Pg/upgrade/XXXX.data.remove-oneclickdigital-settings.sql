BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- OneClickdigital (later RBdigital) was discontinued in 2019; the client
-- integration and its library settings have been removed.

DELETE FROM actor.org_unit_setting
    WHERE name IN (
        'ebook_api.oneclickdigital.base_uri',
        'ebook_api.oneclickdigital.library_id',
        'ebook_api.oneclickdigital.basic_token'
    );

DELETE FROM config.org_unit_setting_type
    WHERE name IN (
        'ebook_api.oneclickdigital.base_uri',
        'ebook_api.oneclickdigital.library_id',
        'ebook_api.oneclickdigital.basic_token'
    );

COMMIT;
