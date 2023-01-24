BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('YYYY', :eg_version);

-- 002.schema.config.sql

-- this may grow to support full GNU gettext functionality
CREATE TABLE config.i18n_string (
    id              SERIAL      PRIMARY KEY,
    context         TEXT        NOT NULL, -- hint for translators to disambiguate
    string          TEXT        NOT NULL
);

-- 950.data.seed-values.sql

INSERT INTO config.i18n_string (id, context, string) VALUES (1,
    oils_i18n_gettext(
        1, 'In the Place Hold interfaces for staff and patrons; when monographic parts are available, this string provides contextual information about whether and how parts are considered for holds that do not request a specific mongraphic part.',
        'i18ns','context'
    ),
    oils_i18n_gettext(
        1, 'All Parts',
        'i18ns','string'
    )
);
SELECT SETVAL('config.i18n_string_id_seq', 10000); -- reserve some for stock EG interfaces

COMMIT;
