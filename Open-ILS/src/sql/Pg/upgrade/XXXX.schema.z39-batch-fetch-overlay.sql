BEGIN;

-- TODO version check

CREATE OR REPLACE FUNCTION 
    evergreen.z3950_name_is_valid(TEXT) RETURNS BOOLEAN AS $func$
    SELECT EXISTS (SELECT 1 FROM config.z3950_attr WHERE name = $1);
$func$ LANGUAGE SQL STRICT IMMUTABLE;


CREATE TABLE config.z3950_index_field_map (
    id              SERIAL  PRIMARY KEY,
    label           TEXT    NOT NULL, -- i18n
    metabib_field   INTEGER REFERENCES config.metabib_field(id),
    record_attr     TEXT    REFERENCES config.record_attr_definition(name),
    z3950_attr      INTEGER REFERENCES config.z3950_attr(id),
    z3950_attr_type TEXT,-- REFERENCES config.z3950_attr(name)
    CONSTRAINT metabib_field_or_record_attr CHECK (
        metabib_field IS NOT NULL OR 
        record_attr IS NOT NULL
    ),
    CONSTRAINT attr_or_attr_type CHECK (
        z3950_attr IS NOT NULL OR 
        z3950_attr_type IS NOT NULL
    ),
    -- ensure the selected z3950_attr_type refers to a valid attr name
    CONSTRAINT valid_z3950_attr_type CHECK (
        z3950_attr_type IS NULL OR 
            evergreen.z3950_name_is_valid(z3950_attr_type)
    )
);

-- seed data

INSERT INTO config.z3950_index_field_map 
    (id, label, metabib_field, z3950_attr_type) VALUES 
(1, oils_i18n_gettext(1, 'Title',   'czifm', 'label'), 5,  'title'),
(2, oils_i18n_gettext(2, 'Author',  'czifm', 'label'), 8,  'author'),
(3, oils_i18n_gettext(3, 'ISBN',    'czifm', 'label'), 18, 'isbn'),
(4, oils_i18n_gettext(4, 'ISSN',    'czifm', 'label'), 19, 'issn'),
(5, oils_i18n_gettext(5, 'LCCN',    'czifm', 'label'), 30, 'lccn');

INSERT INTO config.z3950_index_field_map 
    (id, label, record_attr, z3950_attr_type) VALUES 
(6, oils_i18n_gettext(6, 'Pubdate',  'czifm', 'label'),'pubdate', 'pubdate'),
(7, oils_i18n_gettext(7, 'Item Type', 'czifm', 'label'),'item_type', 'item_type');


-- let's leave room for more stock mappings
SELECT SETVAL('config.z3950_index_field_map_id_seq'::TEXT, 1000);

COMMIT;
