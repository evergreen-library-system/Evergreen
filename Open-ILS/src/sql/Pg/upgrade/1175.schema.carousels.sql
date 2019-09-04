BEGIN;

SELECT evergreen.upgrade_deps_block_check('1175', :eg_version);

CREATE TABLE config.carousel_type (
    id                          SERIAL PRIMARY KEY,
    name                        TEXT NOT NULL,
    automatic                   BOOLEAN NOT NULL DEFAULT TRUE,
    filter_by_age               BOOLEAN NOT NULL DEFAULT FALSE,
    filter_by_copy_owning_lib   BOOLEAN NOT NULL DEFAULT FALSE,
    filter_by_copy_location     BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO config.carousel_type
    (id, name,                               automatic, filter_by_age, filter_by_copy_owning_lib, filter_by_copy_location)
VALUES
    (1, 'Manual',                            FALSE,     FALSE,         FALSE,                     FALSE),
    (2, 'Newly Catalogued Items',            TRUE,      TRUE,          TRUE,                      TRUE),
    (3, 'Recently Returned Items',           TRUE,      TRUE,          TRUE,                      TRUE),
    (4, 'Top Circulated Items',              TRUE,      TRUE,          TRUE,                      FALSE),
    (5, 'Newest Items By Shelving Location', TRUE,      TRUE,          TRUE,                      FALSE)
;

SELECT SETVAL('config.carousel_type_id_seq'::TEXT, 100);

CREATE TABLE container.carousel (
    id                      SERIAL PRIMARY KEY,
    type                    INTEGER NOT NULL REFERENCES config.carousel_type (id),
    owner                   INTEGER NOT NULL REFERENCES actor.org_unit (id),
    name                    TEXT NOT NULL,
    bucket                  INTEGER REFERENCES container.biblio_record_entry_bucket (id),
    creator                 INTEGER NOT NULL REFERENCES actor.usr (id),
    editor                  INTEGER NOT NULL REFERENCES actor.usr (id),
    create_time             TIMESTAMPTZ NOT NULL DEFAULT now(),
    edit_time               TIMESTAMPTZ NOT NULL DEFAULT now(),
    age_filter              INTERVAL,
    owning_lib_filter       INT[],
    copy_location_filter    INT[],
    last_refresh_time       TIMESTAMPTZ,
    active                  BOOLEAN NOT NULL DEFAULT TRUE,
    max_items               INTEGER NOT NULL
);

CREATE TABLE container.carousel_org_unit (
    id              SERIAL PRIMARY KEY,
    carousel        INTEGER NOT NULL REFERENCES container.carousel (id) ON DELETE CASCADE,
    override_name   TEXT,
    org_unit        INTEGER NOT NULL REFERENCES actor.org_unit (id),
    seq             INTEGER NOT NULL
);

INSERT INTO container.biblio_record_entry_bucket_type (code, label) VALUES ('carousel', 'Carousel');

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 612, 'ADMIN_CAROUSEL_TYPE', oils_i18n_gettext(611,
    'Allow a user to manage carousel types', 'ppl', 'description')),
 ( 613, 'ADMIN_CAROUSEL', oils_i18n_gettext(612,
    'Allow a user to manage carousels', 'ppl', 'description')),
 ( 614, 'REFRESH_CAROUSEL', oils_i18n_gettext(613,
    'Allow a user to refresh carousels', 'ppl', 'description'))
;

COMMIT;
