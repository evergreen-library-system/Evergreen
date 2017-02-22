BEGIN;

SELECT evergreen.upgrade_deps_block_check('1028', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype) 
VALUES (
    'ebook_api.overdrive.discovery_base_uri',
    oils_i18n_gettext(
        'ebook_api.overdrive.discovery_base_uri',
        'OverDrive Discovery API Base URI',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.discovery_base_uri',
        'Base URI for OverDrive Discovery API (defaults to https://api.overdrive.com/v1). Using HTTPS here is strongly encouraged.',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.circulation_base_uri',
    oils_i18n_gettext(
        'ebook_api.overdrive.circulation_base_uri',
        'OverDrive Circulation API Base URI',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.circulation_base_uri',
        'Base URI for OverDrive Circulation API (defaults to https://patron.api.overdrive.com/v1). Using HTTPS here is strongly encouraged.',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.account_id',
    oils_i18n_gettext(
        'ebook_api.overdrive.account_id',
        'OverDrive Account ID',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.account_id',
        'Account ID (a.k.a. Library ID) for this library, as assigned by OverDrive',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.websiteid',
    oils_i18n_gettext(
        'ebook_api.overdrive.websiteid',
        'OverDrive Website ID',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.websiteid',
        'Website ID for this library, as assigned by OverDrive',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.authorizationname',
    oils_i18n_gettext(
        'ebook_api.overdrive.authorizationname',
        'OverDrive Authorization Name',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.authorizationname',
        'Authorization name for this library, as assigned by OverDrive',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.basic_token',
    oils_i18n_gettext(
        'ebook_api.overdrive.basic_token',
        'OverDrive Basic Token',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.basic_token',
        'Basic token for client authentication with OverDrive API (supplied by OverDrive)',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.granted_auth_redirect_uri',
    oils_i18n_gettext(
        'ebook_api.overdrive.granted_auth_redirect_uri',
        'OverDrive Granted Authorization Redirect URI',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.granted_auth_redirect_uri',
        'URI provided to OverDrive for use with granted authorization',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.password_required',
    oils_i18n_gettext(
        'ebook_api.overdrive.password_required',
        'OverDrive Password Required',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.password_required',
        'Does this library require a password when authenticating patrons with the OverDrive API?',
        'coust',
        'description'
    ),
    'ebook_api',
    'bool'
);

COMMIT;

