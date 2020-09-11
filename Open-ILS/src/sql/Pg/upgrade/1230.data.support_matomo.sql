BEGIN;

SELECT evergreen.upgrade_deps_block_check('1230', :eg_version);

INSERT INTO permission.perm_list
    ( id, code, description )
VALUES (
    623, 'UPDATE_ORG_UNIT_SETTING.opac.matomo', oils_i18n_gettext(623,
    'Allows a user to configure Matomo Analytics org unit settings', 'ppl', 'description')
);

INSERT into config.org_unit_setting_type
    ( name, grp, label, description, datatype, update_perm )
VALUES (
    'opac.analytics.matomo_id', 'opac',
    oils_i18n_gettext(
    'opac.analytics.matomo_id',
    'Matomo Site ID',
    'coust', 'label'),
    oils_i18n_gettext('opac.analytics.matomo_id',
    'The Site ID for your Evergreen catalog. You can find the Site ID in the tracking code you got from Matomo.',
    'coust', 'description'),
    'string', 623
), (
    'opac.analytics.matomo_url', 'opac',
    oils_i18n_gettext('opac.analytics.matomo_url',
    'Matomo URL',
    'coust', 'label'),
    oils_i18n_gettext('opac.analytics.matomo_url',
    'The URL for your the Matomo software. Be sure to include the trailing slash, e.g. https://my-evergreen.matomo.cloud/',
    'coust', 'description'),
    'string', 623
);

COMMIT;

