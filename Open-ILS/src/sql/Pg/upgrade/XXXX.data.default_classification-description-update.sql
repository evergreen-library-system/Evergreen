BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

UPDATE config.org_unit_setting_type SET description = oils_i18n_gettext('cat.default_classification_scheme',
        'Defines the default classification scheme for new call numbers.',
         'coust', 'description')
    WHERE name = 'cat.default_classification_scheme'

COMMIT;