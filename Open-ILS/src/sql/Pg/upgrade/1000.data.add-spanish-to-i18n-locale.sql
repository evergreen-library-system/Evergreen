-- Add Spanish to config.i18n_locale table

BEGIN;

SELECT evergreen.upgrade_deps_block_check('1000', :eg_version);

INSERT INTO config.i18n_locale (code,marc_code,name,description)
    SELECT 'es-ES', 'spa', oils_i18n_gettext('es-ES', 'Spanish', 'i18n_l', 'name'),
        oils_i18n_gettext('es-ES', 'Spanish', 'i18n_l', 'description')
    WHERE NOT EXISTS (SELECT 1 FROM config.i18n_locale WHERE code = 'es-ES');

COMMIT;
