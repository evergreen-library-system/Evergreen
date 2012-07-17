-- Evergreen DB patch 0723.schema.function.get_locale_name.sql
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0723', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.get_locale_name(
    IN locale TEXT,
    OUT name TEXT,
    OUT description TEXT
) AS $$
DECLARE
    eg_locale TEXT;
BEGIN
    eg_locale := LOWER(SUBSTRING(locale FROM 1 FOR 2)) || '-' || UPPER(SUBSTRING(locale FROM 4 FOR 2));
        
    SELECT i18nc.string INTO name
    FROM config.i18n_locale i18nl
       INNER JOIN config.i18n_core i18nc ON i18nl.code = i18nc.translation
    WHERE i18nc.identity_value = eg_locale
       AND code = eg_locale
       AND i18nc.fq_field = 'i18n_l.name';

    IF name IS NULL THEN
       SELECT i18nl.name INTO name
       FROM config.i18n_locale i18nl
       WHERE code = eg_locale;
    END IF;

    SELECT i18nc.string INTO description
    FROM config.i18n_locale i18nl
       INNER JOIN config.i18n_core i18nc ON i18nl.code = i18nc.translation
    WHERE i18nc.identity_value = eg_locale
       AND code = eg_locale
       AND i18nc.fq_field = 'i18n_l.description';

    IF description IS NULL THEN
       SELECT i18nl.description INTO description
       FROM config.i18n_locale i18nl
       WHERE code = eg_locale;
    END IF;
END;
$$ LANGUAGE PLPGSQL COST 1 STABLE;

COMMIT;
