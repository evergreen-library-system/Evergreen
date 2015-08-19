BEGIN;

SELECT evergreen.upgrade_deps_block_check('0933', :eg_version);


CREATE TABLE config.marc_format (
    id                  SERIAL PRIMARY KEY,
    code                TEXT NOT NULL,
    name                TEXT NOT NULL
);
COMMENT ON TABLE config.marc_format IS $$
List of MARC formats supported by this Evergreen
database. This exists primarily as a hook for future
support of UNIMARC, though whether that will ever
happen remains to be seen.
$$;

CREATE TYPE config.marc_record_type AS ENUM ('biblio', 'authority', 'serial');

CREATE TABLE config.marc_field (
    id                  SERIAL PRIMARY KEY,
    marc_format         INTEGER NOT NULL
                        REFERENCES config.marc_format (id) DEFERRABLE INITIALLY DEFERRED,
    marc_record_type    config.marc_record_type NOT NULL,
    tag                 CHAR(3) NOT NULL,
    name                TEXT,
    description         TEXT,
    fixed_field         BOOLEAN,
    repeatable          BOOLEAN,
    mandatory           BOOLEAN,
    hidden              BOOLEAN,
    owner               INTEGER REFERENCES actor.org_unit (id)
                        -- if the owner is null, the data about the field is
                        -- assumed to come from the controlling MARC standard
);

COMMENT ON TABLE config.marc_field IS $$
This table stores a list of MARC fields recognized by the Evergreen
instance.  Note that we're not aiming for completely generic ISO2709
support: we're assuming things like three characters for a tag,
one-character subfield labels, two indicators per variable data field,
and the like, all of which are technically specializations of ISO2709.

Of particular significance is the owner column; if it's set to a null
value, the field definition is assumed to come from a national
standards body; if it's set to a non-null value, the field definition
is an OU-level addition to or override of the standard.
$$;

CREATE INDEX config_marc_field_tag_idx ON config.marc_field (tag);
CREATE INDEX config_marc_field_owner_idx ON config.marc_field (owner);

CREATE UNIQUE INDEX config_standard_marc_tags_are_unique
    ON config.marc_field(marc_format, marc_record_type, tag)
    WHERE owner IS NULL;
ALTER TABLE config.marc_field
    ADD CONSTRAINT config_standard_marc_tags_are_fully_specified
    CHECK ((owner IS NOT NULL) OR
           (
                owner IS NULL AND
                repeatable IS NOT NULL AND
                mandatory IS NOT NULL AND
                hidden IS NOT NULL
           )
          );

CREATE TABLE config.marc_subfield (
    id                  SERIAL PRIMARY KEY,
    marc_format         INTEGER NOT NULL
                        REFERENCES config.marc_format (id) DEFERRABLE INITIALLY DEFERRED,
    marc_record_type    config.marc_record_type NOT NULL,
    tag                 CHAR(3) NOT NULL,
    code                CHAR(1) NOT NULL,
    description         TEXT,
    repeatable          BOOLEAN,
    mandatory           BOOLEAN,
    hidden              BOOLEAN,
    value_ctype         TEXT
                        REFERENCES config.record_attr_definition (name)
                            DEFERRABLE INITIALLY DEFERRED,
    owner               INTEGER REFERENCES actor.org_unit (id)
                        -- if the owner is null, the data about the subfield is
                        -- assumed to come from the controlling MARC standard
);

COMMENT ON TABLE config.marc_subfield IS $$
This table stores the list of subfields recognized by this Evergreen
instance.  As with config.marc_field, of particular significance is the
owner column; if it's set to a null value, the subfield definition is
assumed to come from a national standards body; if it's set to a non-null
value, the subfield definition is an OU-level addition to or override
of the standard.
$$;

CREATE INDEX config_marc_subfield_tag_code_idx ON config.marc_subfield (tag, code);
CREATE UNIQUE INDEX config_standard_marc_subfields_are_unique
    ON config.marc_subfield(marc_format, marc_record_type, tag, code)
    WHERE owner IS NULL;
ALTER TABLE config.marc_subfield
    ADD CONSTRAINT config_standard_marc_subfields_are_fully_specified
    CHECK ((owner IS NOT NULL) OR
           (
                owner IS NULL AND
                repeatable IS NOT NULL AND
                mandatory IS NOT NULL AND
                hidden IS NOT NULL
           )
          );

CREATE OR REPLACE VIEW config.marc_field_for_ou AS
WITH RECURSIVE ou_marc_fields(id, marc_format, marc_record_type, tag,
                              name, description, fixed_field, repeatable,
                              mandatory, hidden, owner, depth) AS (
    -- start with all MARC fields defined by the controlling national standard
    SELECT id, marc_format, marc_record_type, tag, name, description, fixed_field, repeatable, mandatory, hidden, owner, 0
    FROM config.marc_field
    WHERE owner IS NULL
    UNION
    -- as well as any purely local ones that have been added
    SELECT id, marc_format, marc_record_type, tag, name, description, fixed_field, repeatable, mandatory, hidden, owner, 0
    FROM config.marc_field
    WHERE ARRAY[marc_format::TEXT, marc_record_type::TEXT, tag] NOT IN (
        SELECT ARRAY[marc_format::TEXT, marc_record_type::TEXT, tag]
        FROM config.marc_field
        WHERE owner IS NULL
    )
  UNION
    -- and start walking down the org unit hierarchy,
    -- letting entries for child OUs override field names,
    -- descriptions, repeatability, and the like.  Letting
    -- fixed-fieldness be overridable is something that falls
    -- from the implementation, but is unlikely to be useful
    SELECT c.id, marc_format, marc_record_type, tag,
           COALESCE(c.name, p.name),
           COALESCE(c.description, p.description),
           COALESCE(c.fixed_field, p.fixed_field),
           COALESCE(c.repeatable, p.repeatable),
           COALESCE(c.mandatory, p.mandatory),
           COALESCE(c.hidden, p.hidden),
           c.owner,
           depth + 1
    FROM config.marc_field c
    JOIN ou_marc_fields p USING (marc_format, marc_record_type, tag)
    JOIN actor.org_unit aou ON (c.owner = aou.id)
    WHERE (aou.parent_ou = p.owner OR (aou.parent_ou IS NULL AND p.owner IS NULL))
)
SELECT id, marc_format, marc_record_type, tag,
       name, description, fixed_field, repeatable,
       mandatory, hidden, owner, depth
FROM ou_marc_fields;

CREATE OR REPLACE VIEW config.marc_subfield_for_ou AS
WITH RECURSIVE ou_marc_subfields(id, marc_format, marc_record_type, tag, code,
                              description, repeatable,
                              mandatory, hidden, value_ctype, owner, depth) AS (
    -- start with all MARC subfields defined by the controlling national standard
    SELECT id, marc_format, marc_record_type, tag, code, description, repeatable, mandatory,
           hidden, value_ctype, owner, 0
    FROM config.marc_subfield
    WHERE owner IS NULL
    UNION
    -- as well as any purely local ones that have been added
    SELECT id, marc_format, marc_record_type, tag, code, description, repeatable, mandatory,
           hidden, value_ctype, owner, 0
    FROM config.marc_subfield
    WHERE ARRAY[marc_format::TEXT, marc_record_type::TEXT, tag, code] NOT IN (
        SELECT ARRAY[marc_format::TEXT, marc_record_type::TEXT, tag, code]
        FROM config.marc_subfield
        WHERE owner IS NULL
    )
  UNION
    -- and start walking down the org unit hierarchy,
    -- letting entries for child OUs override subfield
    -- descriptions, repeatability, and the like.
    SELECT c.id, marc_format, marc_record_type, tag, code,
           COALESCE(c.description, p.description),
           COALESCE(c.repeatable, p.repeatable),
           COALESCE(c.mandatory, p.mandatory),
           COALESCE(c.hidden, p.hidden),
           COALESCE(c.value_ctype, p.value_ctype),
           c.owner,
           depth + 1
    FROM config.marc_subfield c
    JOIN ou_marc_subfields p USING (marc_format, marc_record_type, tag, code)
    JOIN actor.org_unit aou ON (c.owner = aou.id)
    WHERE (aou.parent_ou = p.owner OR (aou.parent_ou IS NULL AND p.owner IS NULL))
)
SELECT id, marc_format, marc_record_type, tag, code,
       description, repeatable,
       mandatory, hidden, value_ctype, owner, depth
FROM ou_marc_subfields;

CREATE OR REPLACE FUNCTION config.ou_marc_fields(marc_format INTEGER, marc_record_type config.marc_record_type, ou INTEGER) RETURNS SETOF config.marc_field AS $func$
    SELECT id, marc_format, marc_record_type, tag, name, description, fixed_field, repeatable, mandatory, hidden, owner
    FROM (
        SELECT id, marc_format, marc_record_type, tag, name, description,
              fixed_field, repeatable, mandatory, hidden, owner, depth,
              MAX(depth) OVER (PARTITION BY marc_format, marc_record_type, tag) AS winner
        FROM config.marc_field_for_ou
        WHERE (owner IS NULL
               OR owner IN (SELECT id FROM actor.org_unit_ancestors($3)))
        AND   marc_format = $1
        AND   marc_record_type = $2
    ) AS s
    WHERE depth = winner
    AND not hidden;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION config.ou_marc_subfields(marc_format INTEGER, marc_record_type config.marc_record_type, ou INTEGER) RETURNS SETOF config.marc_subfield AS $func$
    SELECT id, marc_format, marc_record_type, tag, code, description, repeatable, mandatory,
           hidden, value_ctype, owner
    FROM (
        SELECT id, marc_format, marc_record_type, tag, code, description,
              repeatable, mandatory, hidden, value_ctype, owner, depth,
              MAX(depth) OVER (PARTITION BY marc_format, marc_record_type, tag, code) AS winner
        FROM config.marc_subfield_for_ou
        WHERE (owner IS NULL
               OR owner IN (SELECT id FROM actor.org_unit_ancestors($3)))
        AND   marc_format = $1
        AND   marc_record_type = $2
    ) AS s
    WHERE depth = winner
    AND not hidden;
$func$ LANGUAGE SQL;

COMMIT;
