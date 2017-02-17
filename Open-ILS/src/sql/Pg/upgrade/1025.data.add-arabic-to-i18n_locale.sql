BEGIN;

SELECT evergreen.upgrade_deps_block_check('1025', :eg_version);

-- Add Arabic (Jordan) to i18n_locale table as a stock language option
INSERT INTO config.i18n_locale (code,marc_code,name,description,rtl)
    VALUES ('ar-JO', 'ara', oils_i18n_gettext('ar-JO', 'Arabic (Jordan)', 'i18n_l', 'name'),
        oils_i18n_gettext('ar-JO', 'Arabic (Jordan)', 'i18n_l', 'description'), 'true');

COMMIT;

