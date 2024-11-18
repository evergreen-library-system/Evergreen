/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2008  Equinox Software, Inc.
 * Copyright (C) 2010  Laurentian University
 * Mike Rylander <miker@esilibrary.com> 
 * Dan Scott <dscott@laurentian.ca>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

DROP SCHEMA IF EXISTS authority CASCADE;

BEGIN;
CREATE SCHEMA authority;

-- subset of types listed in https://www.loc.gov/marc/authority/ad1xx3xx.html
-- for now, ignoring subdivisions
CREATE TYPE authority.heading_type AS ENUM (
    'personal_name',
    'corporate_name',
    'meeting_name',
    'uniform_title',
    'named_event',
    'chronological_term',
    'topical_term',
    'geographic_name',
    'genre_form_term',
    'medium_of_performance_term'
);

CREATE TYPE authority.variant_heading_type AS ENUM (
    'abbreviation',
    'acronym',
    'translation',
    'expansion',
    'other',
    'hidden'
);

CREATE TYPE authority.related_heading_type AS ENUM (
    'earlier',
    'later',
    'parent organization',
    'broader',
    'narrower',
    'equivalent',
    'other'
);

CREATE TYPE authority.heading_purpose AS ENUM (
    'main',
    'variant',
    'related'
);

CREATE TABLE authority.heading_field (
    id              SERIAL                      PRIMARY KEY,
    heading_type    authority.heading_type      NOT NULL,
    heading_purpose authority.heading_purpose   NOT NULL,
    label           TEXT                        NOT NULL,
    format          TEXT                        NOT NULL REFERENCES config.xml_transform (name) DEFAULT 'mads21',
    heading_xpath   TEXT                        NOT NULL,
    component_xpath TEXT                        NOT NULL,
    type_xpath      TEXT                        NULL, -- to extract related or variant type
    thesaurus_xpath TEXT                        NULL,
    thesaurus_override_xpath TEXT               NULL,
    joiner          TEXT                        NULL
);

CREATE TABLE authority.heading_field_norm_map (
        id      SERIAL  PRIMARY KEY,
        field   INT     NOT NULL REFERENCES authority.heading_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        norm    INT     NOT NULL REFERENCES config.index_normalizer (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        params  TEXT,
        pos     INT     NOT NULL DEFAULT 0
);

CREATE TYPE authority.heading AS (
    field               INT,
    type                authority.heading_type,
    purpose             authority.heading_purpose,
    variant_type        authority.variant_heading_type,
    related_type        authority.related_heading_type,
    thesaurus           TEXT,
    heading             TEXT,
    normalized_heading  TEXT
);

CREATE TABLE authority.control_set (
    id          SERIAL  PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE, -- i18n
    description TEXT                     -- i18n
);

CREATE TABLE authority.control_set_authority_field (
    id          SERIAL  PRIMARY KEY,
    main_entry  INT     REFERENCES authority.control_set_authority_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    control_set INT     NOT NULL REFERENCES authority.control_set (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    tag         CHAR(3) NOT NULL,
    nfi         CHAR(1),          -- non-filing indicator
    sf_list     TEXT    NOT NULL,
    display_sf_list     TEXT NOT NULL,
    name        TEXT    NOT NULL, -- i18n
    description TEXT,             -- i18n
    joiner      TEXT,
    linking_subfield CHAR(1),
    heading_field INTEGER REFERENCES authority.heading_field(id)
);

CREATE TABLE authority.control_set_bib_field (
    id              SERIAL  PRIMARY KEY,
    authority_field INT     NOT NULL REFERENCES authority.control_set_authority_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    tag             CHAR(3) NOT NULL
);

-- Seed data will be generated from class <-> axis mapping
CREATE TABLE authority.control_set_bib_field_metabib_field_map (
    id              SERIAL  PRIMARY KEY,
    bib_field       INT     NOT NULL REFERENCES authority.control_set_bib_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    metabib_field   INT     NOT NULL REFERENCES config.metabib_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT a_bf_mf_map_once UNIQUE (bib_field, metabib_field)
);

CREATE VIEW authority.control_set_auth_field_metabib_field_map_main AS
    SELECT  DISTINCT b.authority_field, m.metabib_field
      FROM  authority.control_set_bib_field_metabib_field_map m JOIN authority.control_set_bib_field b ON (b.id = m.bib_field);
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_main IS $$metabib fields for main entry auth fields$$;

CREATE VIEW authority.control_set_auth_field_metabib_field_map_refs_only AS
    SELECT  DISTINCT a.id AS authority_field, m.metabib_field
      FROM  authority.control_set_authority_field a
            JOIN authority.control_set_authority_field ame ON (a.main_entry = ame.id)
            JOIN authority.control_set_bib_field b ON (b.authority_field = ame.id)
            JOIN authority.control_set_bib_field_metabib_field_map mf ON (mf.bib_field = b.id)
            JOIN authority.control_set_auth_field_metabib_field_map_main m ON (ame.id = m.authority_field);
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_refs_only IS $$metabib fields for NON-main entry auth fields$$;

CREATE VIEW authority.control_set_auth_field_metabib_field_map_refs AS
    SELECT * FROM authority.control_set_auth_field_metabib_field_map_main
        UNION
    SELECT * FROM authority.control_set_auth_field_metabib_field_map_refs_only;
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_refs IS $$metabib fields for all auth fields$$;


-- blind refs only is probably what we want for lookup in bib/auth browse
CREATE VIEW authority.control_set_auth_field_metabib_field_map_blind_refs_only AS
    SELECT  r.*
      FROM  authority.control_set_auth_field_metabib_field_map_refs_only r
            JOIN authority.control_set_authority_field a ON (r.authority_field = a.id)
      WHERE linking_subfield IS NULL;
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_blind_refs_only IS $$metabib fields for NON-main entry auth fields that can't be linked to other records$$; -- '

CREATE VIEW authority.control_set_auth_field_metabib_field_map_blind_refs AS
    SELECT  r.*
      FROM  authority.control_set_auth_field_metabib_field_map_refs r
            JOIN authority.control_set_authority_field a ON (r.authority_field = a.id)
      WHERE linking_subfield IS NULL;
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_blind_refs IS $$metabib fields for all auth fields that can't be linked to other records$$; -- '

CREATE VIEW authority.control_set_auth_field_metabib_field_map_blind_main AS
    SELECT  r.*
      FROM  authority.control_set_auth_field_metabib_field_map_main r
            JOIN authority.control_set_authority_field a ON (r.authority_field = a.id)
      WHERE linking_subfield IS NULL;
COMMENT ON VIEW authority.control_set_auth_field_metabib_field_map_blind_main IS $$metabib fields for main entry auth fields that can't be linked to other records$$; -- '

CREATE TABLE authority.thesaurus (
    code        TEXT    PRIMARY KEY,     -- MARC21 thesaurus code
    control_set INT     REFERENCES authority.control_set (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name        TEXT    NOT NULL UNIQUE, -- i18n
    description TEXT,                     -- i18n
    short_code  TEXT,
    uri         TEXT
);

CREATE TRIGGER thes_code_tracking_trigger
    AFTER UPDATE ON authority.thesaurus
    FOR EACH ROW EXECUTE PROCEDURE oils_i18n_code_tracking('at');

CREATE TABLE authority.browse_axis (
    code        TEXT    PRIMARY KEY,
    name        TEXT    UNIQUE NOT NULL, -- i18n
    sorter      TEXT    REFERENCES config.record_attr_definition (name) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    description TEXT
);

CREATE TABLE authority.browse_axis_authority_field_map (
    id          SERIAL  PRIMARY KEY,
    axis        TEXT    NOT NULL REFERENCES authority.browse_axis (code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    field       INT     NOT NULL REFERENCES authority.control_set_authority_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE authority.record_entry (
    id              BIGSERIAL    PRIMARY KEY,
    create_date     TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now(),
    edit_date       TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now(),
    creator         INT     NOT NULL DEFAULT 1,
    editor          INT     NOT NULL DEFAULT 1,
    active          BOOL    NOT NULL DEFAULT TRUE,
    deleted         BOOL    NOT NULL DEFAULT FALSE,
    source          INT,
    control_set     INT     REFERENCES authority.control_set (id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    marc            TEXT    NOT NULL,
    last_xact_id    TEXT    NOT NULL,
    owner           INT,
    heading         TEXT,
    simple_heading  TEXT
);
CREATE INDEX authority_record_entry_creator_idx ON authority.record_entry ( creator );
CREATE INDEX authority_record_entry_editor_idx ON authority.record_entry ( editor );
CREATE INDEX authority_record_entry_create_date_idx ON authority.record_entry ( create_date );
CREATE INDEX authority_record_entry_edit_date_idx ON authority.record_entry ( edit_date );
CREATE INDEX authority_record_deleted_idx ON authority.record_entry(deleted) WHERE deleted IS FALSE OR deleted = false;
CREATE TRIGGER a_marcxml_is_well_formed BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.check_marcxml_well_formed();
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_901();
CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_control_numbers();

CREATE TABLE authority.authority_linking (
    id      BIGSERIAL PRIMARY KEY,
    source  BIGINT REFERENCES authority.record_entry (id) NOT NULL,
    target  BIGINT REFERENCES authority.record_entry (id) NOT NULL,
    field   INT REFERENCES authority.control_set_authority_field (id) NOT NULL
);

CREATE TABLE authority.bib_linking (
    id          BIGSERIAL   PRIMARY KEY,
    bib         BIGINT      NOT NULL REFERENCES biblio.record_entry (id),
    authority   BIGINT      NOT NULL REFERENCES authority.record_entry (id)
);
CREATE INDEX authority_bl_bib_idx ON authority.bib_linking ( bib );
CREATE UNIQUE INDEX authority_bl_bib_authority_once_idx ON authority.bib_linking ( authority, bib );

CREATE TABLE authority.record_note (
    id          BIGSERIAL   PRIMARY KEY,
    record      BIGINT      NOT NULL REFERENCES authority.record_entry (id) DEFERRABLE INITIALLY DEFERRED,
    value       TEXT        NOT NULL,
    creator     INT         NOT NULL DEFAULT 1,
    editor      INT         NOT NULL DEFAULT 1,
    create_date TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now(),
    edit_date   TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now()
);
CREATE INDEX authority_record_note_record_idx ON authority.record_note ( record );
CREATE INDEX authority_record_note_creator_idx ON authority.record_note ( creator );
CREATE INDEX authority_record_note_editor_idx ON authority.record_note ( editor );

CREATE TABLE authority.rec_descriptor (
    id              BIGSERIAL PRIMARY KEY,
    record          BIGINT,
    record_status   TEXT,
    encoding_level  TEXT,
    thesaurus       TEXT
);
CREATE INDEX authority_rec_descriptor_record_idx ON authority.rec_descriptor (record);

CREATE TABLE authority.full_rec (
    id              BIGSERIAL   PRIMARY KEY,
    record          BIGINT      NOT NULL,
    tag             CHAR(3)     NOT NULL,
    ind1            TEXT,
    ind2            TEXT,
    subfield        TEXT,
    value           TEXT        NOT NULL,
    index_vector    tsvector    NOT NULL
);
CREATE INDEX authority_full_rec_record_idx ON authority.full_rec (record);
CREATE INDEX authority_full_rec_tag_subfield_idx ON authority.full_rec (tag, subfield);
CREATE INDEX authority_full_rec_tag_part_idx ON authority.full_rec (SUBSTRING(tag FROM 2));
CREATE INDEX authority_full_rec_subfield_a_idx ON authority.full_rec (value) WHERE subfield = 'a';
CREATE TRIGGER authority_full_rec_fti_trigger
    BEFORE UPDATE OR INSERT ON authority.full_rec
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE INDEX authority_full_rec_index_vector_idx ON authority.full_rec USING GIN (index_vector);
/* Enable LIKE to use an index for database clusters with locales other than C or POSIX */
CREATE INDEX authority_full_rec_value_tpo_index ON authority.full_rec (SUBSTRING(value FOR 1024) text_pattern_ops);
/* But we still need this (boooo) for paging using >, <, etc */
CREATE INDEX authority_full_rec_value_index ON authority.full_rec (SUBSTRING(value FOR 1024));

CREATE RULE protect_authority_rec_delete AS ON DELETE TO authority.record_entry DO INSTEAD (UPDATE authority.record_entry SET deleted = TRUE WHERE OLD.id = authority.record_entry.id; DELETE FROM authority.full_rec WHERE record = OLD.id);

CREATE OR REPLACE FUNCTION authority.extract_thesaurus( marcxml TEXT ) RETURNS TEXT AS $func$
DECLARE
    thes_code TEXT;
BEGIN
    thes_code := vandelay.marc21_extract_fixed_field(marcxml,'Subj');
    IF thes_code IS NULL THEN
        thes_code := '|';
    ELSIF thes_code = 'z' THEN
        thes_code := COALESCE( oils_xpath_string('//*[@tag="040"]/*[@code="f"][1]', marcxml), 'z' );
    ELSE
        SELECT code INTO thes_code FROM authority.thesaurus WHERE short_code = thes_code;
        IF NOT FOUND THEN
            thes_code := '|'; -- default
        END IF;
    END IF;
    RETURN thes_code;
END;
$func$ LANGUAGE PLPGSQL STABLE STRICT;

-- Intended to be used in a unique index on authority.record_entry like so:
-- CREATE UNIQUE INDEX unique_by_heading_and_thesaurus
--   ON authority.record_entry (heading)
--   WHERE deleted IS FALSE or deleted = FALSE;
CREATE OR REPLACE FUNCTION authority.normalize_heading( marcxml TEXT, no_thesaurus BOOL ) RETURNS TEXT AS $func$
DECLARE
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    sf_node         TEXT;
    tag_node        TEXT;
    thes_code       TEXT;
    cset            INT;
    heading_text    TEXT;
    tmp_text        TEXT;
    first_sf        BOOL;
    auth_id         INT DEFAULT COALESCE(NULLIF(oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml), ''), '0')::INT;
BEGIN
    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN (SELECT UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]))
          LIMIT 1;
    END IF;

    heading_text := '';
    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset AND main_entry IS NULL LOOP
        tag_used := acsaf.tag;
        nfi_used := acsaf.nfi;
        first_sf := TRUE;

        FOR tag_node IN SELECT unnest(oils_xpath('//*[@tag="'||tag_used||'"]',marcxml))
        LOOP
            FOR sf_node IN SELECT unnest(oils_xpath('//*[local-name() = "subfield" and contains("'||acsaf.sf_list||'",@code)]',tag_node))
            LOOP

                tmp_text := oils_xpath_string('.', sf_node);
                sf := oils_xpath_string('//*/@code', sf_node);

                IF first_sf AND tmp_text IS NOT NULL AND nfi_used IS NOT NULL THEN

                    tmp_text := SUBSTRING(
                        tmp_text FROM
                        COALESCE(
                            NULLIF(
                                REGEXP_REPLACE(
                                    oils_xpath_string('//*[local-name() = "datafield"]/@ind'||nfi_used, tag_node),
                                    $$\D+$$,
                                    '',
                                    'g'
                                ),
                                ''
                            )::INT,
                            0
                        ) + 1
                    );

                END IF;

                first_sf := FALSE;

                IF tmp_text IS NOT NULL AND tmp_text <> '' THEN
                    heading_text := heading_text || E'\u2021' || sf || ' ' || tmp_text;
                END IF;
            END LOOP;

            EXIT WHEN heading_text <> '';
        END LOOP;

        EXIT WHEN heading_text <> '';
    END LOOP;

    IF heading_text <> '' THEN
        IF no_thesaurus IS TRUE THEN
            heading_text := tag_used || ' ' || public.naco_normalize(heading_text);
        ELSE
            thes_code := authority.extract_thesaurus(marcxml);
            heading_text := tag_used || '_' || COALESCE(nfi_used,'-') || '_' || thes_code || ' ' || public.naco_normalize(heading_text);
        END IF;
    ELSE
        heading_text := 'NOHEADING_' || thes_code || ' ' || MD5(marcxml);
    END IF;

    RETURN heading_text;
END;
$func$ LANGUAGE PLPGSQL STABLE STRICT;

CREATE TABLE authority.simple_heading (
    id              BIGSERIAL   PRIMARY KEY,
    record          BIGINT      NOT NULL REFERENCES authority.record_entry (id),
    atag            INT         NOT NULL REFERENCES authority.control_set_authority_field (id),
    value           TEXT        NOT NULL,
    sort_value      TEXT        NOT NULL,
    index_vector    tsvector    NOT NULL,
    thesaurus       TEXT
);
CREATE TRIGGER authority_simple_heading_fti_trigger
    BEFORE UPDATE OR INSERT ON authority.simple_heading
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE INDEX authority_simple_heading_index_vector_idx ON authority.simple_heading USING GIN (index_vector);
CREATE INDEX authority_simple_heading_value_idx ON authority.simple_heading (value);
CREATE INDEX authority_simple_heading_sort_value_idx ON authority.simple_heading (sort_value);
CREATE INDEX authority_simple_heading_record_idx ON authority.simple_heading (record);
CREATE INDEX authority_simple_heading_thesaurus_idx ON authority.simple_heading (thesaurus);

CREATE OR REPLACE FUNCTION authority.simple_heading_set( marcxml TEXT ) RETURNS SETOF authority.simple_heading AS $func$
DECLARE
    res             authority.simple_heading%ROWTYPE;
    acsaf           authority.control_set_authority_field%ROWTYPE;
    heading_row     authority.heading%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    cset            INT;
    heading_text    TEXT;
    joiner_text     TEXT;
    sort_text       TEXT;
    tmp_text        TEXT;
    tmp_xml         TEXT;
    first_sf        BOOL;
    auth_id         INT DEFAULT COALESCE(NULLIF(oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml), ''), '0')::INT;
BEGIN

    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN ( SELECT  UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]))
          LIMIT 1;
    END IF;

    res.record := auth_id;
    res.thesaurus := authority.extract_thesaurus(marcxml);

    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP
        res.atag := acsaf.id;

        IF acsaf.heading_field IS NULL THEN
            tag_used := acsaf.tag;
            nfi_used := acsaf.nfi;
            joiner_text := COALESCE(acsaf.joiner, ' ');

            FOR tmp_xml IN SELECT UNNEST(XPATH('//*[@tag="'||tag_used||'"]', marcxml::XML)::TEXT[]) LOOP

                heading_text := COALESCE(
                    oils_xpath_string('//*[local-name()="subfield" and contains("'||acsaf.display_sf_list||'",@code)]', tmp_xml, joiner_text),
                    ''
                );

                IF nfi_used IS NOT NULL THEN

                    sort_text := SUBSTRING(
                        heading_text FROM
                        COALESCE(
                            NULLIF(
                                REGEXP_REPLACE(
                                    oils_xpath_string('//*[local-name()="datafield"]/@ind'||nfi_used, tmp_xml::TEXT),
                                    $$\D+$$,
                                    '',
                                    'g'
                                ),
                                ''
                            )::INT,
                            0
                        ) + 1
                    );

                ELSE
                    sort_text := heading_text;
                END IF;

                IF heading_text IS NOT NULL AND heading_text <> '' THEN
                    res.value := heading_text;
                    res.sort_value := public.naco_normalize(sort_text);
                    res.index_vector = to_tsvector('keyword'::regconfig, res.sort_value);
                    RETURN NEXT res;
                END IF;

            END LOOP;
        ELSE
            FOR heading_row IN SELECT * FROM authority.extract_headings(marcxml, ARRAY[acsaf.heading_field]) LOOP
                res.value := heading_row.heading;
                res.sort_value := heading_row.normalized_heading;
                res.index_vector = to_tsvector('keyword'::regconfig, res.sort_value);
                RETURN NEXT res;
            END LOOP;
        END IF;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL STABLE STRICT;

CREATE OR REPLACE FUNCTION authority.simple_normalize_heading( marcxml TEXT ) RETURNS TEXT AS $func$
    SELECT authority.normalize_heading($1, TRUE);
$func$ LANGUAGE SQL STABLE STRICT;

CREATE OR REPLACE FUNCTION authority.normalize_heading( marcxml TEXT ) RETURNS TEXT AS $func$
    SELECT authority.normalize_heading($1, FALSE);
$func$ LANGUAGE SQL STABLE STRICT;

COMMENT ON FUNCTION authority.normalize_heading( TEXT ) IS $$
Extract the authority heading, thesaurus, and NACO-normalized values
from an authority record. The primary purpose is to build a unique
index to defend against duplicated authority records from the same
thesaurus.
$$;

-- Store these in line with the MARC for easier indexing
CREATE OR REPLACE FUNCTION authority.normalize_heading_for_upsert () RETURNS TRIGGER AS $f$
BEGIN
    NEW.heading := authority.normalize_heading( NEW.marc );
    NEW.simple_heading := authority.simple_normalize_heading( NEW.marc );
    RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER update_headings_tgr BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE authority.normalize_heading_for_upsert();

-- Adding indexes using oils_xpath_string() for the main entry tags described in
-- authority.control_set_authority_field would speed this up, if we ever want to use it, though
-- the existing index on authority.normalize_heading() helps already with a record in hand
CREATE OR REPLACE VIEW authority.tracing_links AS
    SELECT  main.record AS record,
            main.id AS main_id,
            main.tag AS main_tag,
            oils_xpath_string('//*[@tag="'||main.tag||'"]/*[local-name()="subfield"]', are.marc) AS main_value,
            substr(link.value,1,1) AS relationship,
            substr(link.value,2,1) AS use_restriction,
            substr(link.value,3,1) AS deprecation,
            substr(link.value,4,1) AS display_restriction,
            link.id AS link_id,
            link.tag AS link_tag,
            oils_xpath_string('//*[@tag="'||link.tag||'"]/*[local-name()="subfield"]', are.marc) AS link_value,
            are.heading AS normalized_main_value
      FROM  authority.full_rec main
            JOIN authority.record_entry are ON (main.record = are.id)
            JOIN authority.control_set_authority_field main_entry
                ON (main_entry.tag = main.tag
                    AND main_entry.main_entry IS NULL
                    AND main.subfield = 'a' )
            JOIN authority.control_set_authority_field sub_entry
                ON (main_entry.id = sub_entry.main_entry)
            JOIN authority.full_rec link
                ON (link.record = main.record
                    AND link.tag = sub_entry.tag
                    AND link.subfield = 'w' );

-- Function to generate an ephemeral overlay template from an authority record
CREATE OR REPLACE FUNCTION authority.generate_overlay_template (source_xml TEXT) RETURNS TEXT AS $f$
DECLARE
    cset                INT;
    main_entry          authority.control_set_authority_field%ROWTYPE;
    bib_field           authority.control_set_bib_field%ROWTYPE;
    auth_id             INT DEFAULT oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', source_xml)::INT;
    tmp_data            XML;
    replace_data        XML[] DEFAULT '{}'::XML[];
    replace_rules       TEXT[] DEFAULT '{}'::TEXT[];
    auth_field          XML[];
    auth_i1             TEXT;
    auth_i2             TEXT;
BEGIN
    IF auth_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Default to the LoC crontrol set
    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    -- if none, make a best guess
    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN (
                    SELECT  UNNEST(XPATH('//*[local-name()="datafield" and starts-with(@tag,"1")]/@tag',marc::XML)::TEXT[])
                      FROM  authority.record_entry
                      WHERE id = auth_id
                )
          LIMIT 1;
    END IF;

    -- if STILL none, no-op change
    IF cset IS NULL THEN
        RETURN XMLELEMENT(
            name record,
            XMLATTRIBUTES('http://www.loc.gov/MARC21/slim' AS xmlns),
            XMLELEMENT( name leader, '00881nam a2200193   4500'),
            XMLELEMENT(
                name datafield,
                XMLATTRIBUTES( '905' AS tag, ' ' AS ind1, ' ' AS ind2),
                XMLELEMENT(
                    name subfield,
                    XMLATTRIBUTES('d' AS code),
                    '901c'
                )
            )
        )::TEXT;
    END IF;

    FOR main_entry IN SELECT * FROM authority.control_set_authority_field acsaf WHERE acsaf.control_set = cset AND acsaf.main_entry IS NULL ORDER BY acsaf.tag LOOP
        auth_field := XPATH('//*[local-name()="datafield" and @tag="'||main_entry.tag||'"][1]',source_xml::XML);
        auth_i1 := (XPATH('//*[local-name()="datafield"]/@ind1',auth_field[1]))[1];
        auth_i2 := (XPATH('//*[local-name()="datafield"]/@ind2',auth_field[1]))[1];
        IF ARRAY_LENGTH(auth_field,1) > 0 THEN
            FOR bib_field IN SELECT * FROM authority.control_set_bib_field WHERE authority_field = main_entry.id ORDER BY control_set_bib_field.tag LOOP
                SELECT XMLELEMENT( -- XMLAGG avoids magical <element> creation, but requires unnest subquery
                    name datafield,
                    XMLATTRIBUTES(bib_field.tag AS tag, auth_i1 AS ind1, auth_i2 AS ind2),
                    XMLAGG(UNNEST)
                ) INTO tmp_data FROM UNNEST(XPATH('//*[local-name()="subfield"]', auth_field[1]));
                replace_data := replace_data || tmp_data;
                replace_rules := replace_rules || ( bib_field.tag || main_entry.sf_list || E'[0~\\)' || auth_id || '$]' );
                tmp_data = NULL;
            END LOOP;
            EXIT;
        END IF;
    END LOOP;

    SELECT XMLAGG(UNNEST) INTO tmp_data FROM UNNEST(replace_data);

    RETURN XMLELEMENT(
        name record,
        XMLATTRIBUTES('http://www.loc.gov/MARC21/slim' AS xmlns),
        XMLELEMENT( name leader, '00881nam a2200193   4500'),
        tmp_data,
        XMLELEMENT(
            name datafield,
            XMLATTRIBUTES( '905' AS tag, ' ' AS ind1, ' ' AS ind2),
            XMLELEMENT(
                name subfield,
                XMLATTRIBUTES('r' AS code),
                ARRAY_TO_STRING(replace_rules,',')
            )
        )
    )::TEXT;
END;
$f$ STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( BIGINT ) RETURNS TEXT AS $func$
    SELECT authority.generate_overlay_template( marc ) FROM authority.record_entry WHERE id = $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.merge_records ( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    bib_id        INT := 0;
    bib_rec       biblio.record_entry%ROWTYPE;
    auth_link     authority.bib_linking%ROWTYPE;
    ingest_same   boolean;
BEGIN

    -- Defining our terms:
    -- "target record" = the record that will survive the merge
    -- "source record" = the record that is sacrifing its existence and being
    --   replaced by the target record

    -- 1. Update all bib records with the ID from target_record in their $0
    FOR bib_rec IN
            SELECT  bre.*
              FROM  biblio.record_entry bre 
                    JOIN authority.bib_linking abl ON abl.bib = bre.id
              WHERE abl.authority = source_record
        LOOP

        UPDATE  biblio.record_entry
          SET   marc = REGEXP_REPLACE(
                    marc,
                    E'(<subfield\\s+code="0"\\s*>[^<]*?\\))' || source_record || '<',
                    E'\\1' || target_record || '<',
                    'g'
                )
          WHERE id = bib_rec.id;

          moved_objects := moved_objects + 1;
    END LOOP;

    -- 2. Grab the current value of reingest on same MARC flag
    SELECT  enabled INTO ingest_same
      FROM  config.internal_flag
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    -- 3. Temporarily set reingest on same to TRUE
    UPDATE  config.internal_flag
      SET   enabled = TRUE
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    -- 4. Make a harmless update to target_record to trigger auto-update
    --    in linked bibliographic records
    UPDATE  authority.record_entry
      SET   deleted = FALSE
      WHERE id = target_record;

    -- 5. "Delete" source_record
    DELETE FROM authority.record_entry WHERE id = source_record;

    -- 6. Set "reingest on same MARC" flag back to initial value
    UPDATE  config.internal_flag
      SET   enabled = ingest_same
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;


-- Support function used to find the pivot for alpha-heading-browse style searching
CREATE OR REPLACE FUNCTION authority.simple_heading_find_pivot( a INT[], q TEXT, thesauruses TEXT DEFAULT '' ) RETURNS TEXT AS $$
DECLARE
    sort_value_row  RECORD;
    value_row       RECORD;
    t_term          TEXT;
BEGIN

    t_term := public.naco_normalize(q);

    SELECT  CASE WHEN ash.sort_value LIKE t_term || '%' THEN 1 ELSE 0 END
                + CASE WHEN ash.value LIKE t_term || '%' THEN 1 ELSE 0 END AS rank,
            ash.sort_value
      INTO  sort_value_row
      FROM  authority.simple_heading ash
      WHERE ash.atag = ANY (a)
            AND ash.sort_value >= t_term
            AND CASE thesauruses
                WHEN '' THEN TRUE
                ELSE ash.thesaurus = ANY(regexp_split_to_array(thesauruses, ','))
                END
      ORDER BY rank DESC, ash.sort_value
      LIMIT 1;

    SELECT  CASE WHEN ash.sort_value LIKE t_term || '%' THEN 1 ELSE 0 END
                + CASE WHEN ash.value LIKE t_term || '%' THEN 1 ELSE 0 END AS rank,
            ash.sort_value
      INTO  value_row
      FROM  authority.simple_heading ash
      WHERE ash.atag = ANY (a)
            AND ash.value >= t_term
            AND CASE thesauruses
                WHEN '' THEN TRUE
                ELSE ash.thesaurus = ANY(regexp_split_to_array(thesauruses, ','))
                END
      ORDER BY rank DESC, ash.sort_value
      LIMIT 1;

    IF value_row.rank > sort_value_row.rank THEN
        RETURN value_row.sort_value;
    ELSE
        RETURN sort_value_row.sort_value;
    END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.simple_heading_browse_center( atag_list INT[], q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
DECLARE
    pivot_sort_value    TEXT;
    boffset             INT DEFAULT 0;
    aoffset             INT DEFAULT 0;
    blimit              INT DEFAULT 0;
    alimit              INT DEFAULT 0;
BEGIN

    pivot_sort_value := authority.simple_heading_find_pivot(atag_list,q,thesauruses);

    IF page = 0 THEN
        blimit := pagesize / 2;
        alimit := blimit;

        IF pagesize % 2 <> 0 THEN
            alimit := alimit + 1;
        END IF;
    ELSE
        blimit := pagesize;
        alimit := blimit;

        boffset := pagesize / 2;
        aoffset := boffset;

        IF pagesize % 2 <> 0 THEN
            boffset := boffset + 1;
        END IF;
    END IF;

    IF page <= 0 THEN
        RETURN QUERY
            -- "bottom" half of the browse results
            SELECT id FROM (
                SELECT  ash.id,
                        row_number() over ()
                  FROM  authority.simple_heading ash
                  WHERE ash.atag = ANY (atag_list)
                        AND CASE thesauruses
                            WHEN '' THEN TRUE
                            ELSE ash.thesaurus = ANY(regexp_split_to_array(thesauruses, ','))
                            END
                        AND ash.sort_value < pivot_sort_value
                  ORDER BY ash.sort_value DESC
                  LIMIT blimit
                  OFFSET ABS(page) * pagesize - boffset
            ) x ORDER BY row_number DESC;
    END IF;

    IF page >= 0 THEN
        RETURN QUERY
            -- "bottom" half of the browse results
            SELECT  ash.id
              FROM  authority.simple_heading ash
              WHERE ash.atag = ANY (atag_list)
                    AND CASE thesauruses
                        WHEN '' THEN TRUE
                        ELSE ash.thesaurus = ANY(regexp_split_to_array(thesauruses, ','))
                        END
                    AND ash.sort_value >= pivot_sort_value
              ORDER BY ash.sort_value
              LIMIT alimit
              OFFSET ABS(page) * pagesize - aoffset;
    END IF;
END;
$$ LANGUAGE PLPGSQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_authority_tags(a TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(field) FROM authority.browse_axis_authority_field_map WHERE axis = $1;
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION authority.axis_authority_tags_refs(a TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
       SELECT  unnest(ARRAY_CAT(
                 ARRAY[a.field],
                 (SELECT ARRAY_AGG(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.field)
             )) y
       FROM  authority.browse_axis_authority_field_map a
       WHERE axis = $1) x
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION authority.btag_authority_tags(btag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(authority_field) FROM authority.control_set_bib_field WHERE tag = $1
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION authority.btag_authority_tags_refs(btag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.authority_field],
                    (SELECT ARRAY_AGG(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.authority_field)
                )) y
      FROM  authority.control_set_bib_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION authority.atag_authority_tags(atag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(id) FROM authority.control_set_authority_field WHERE tag = $1
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.atag_authority_tags_refs(atag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.id],
                    (SELECT ARRAY_AGG(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.id)
                )) y
      FROM  authority.control_set_authority_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION authority.axis_browse_center( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.axis_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_browse_center( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.btag_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_browse_center( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.atag_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_browse_center_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.axis_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_browse_center_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.btag_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_browse_center_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.atag_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;


CREATE OR REPLACE FUNCTION authority.simple_heading_browse_top( atag_list INT[], q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
DECLARE
    pivot_sort_value    TEXT;
BEGIN

    pivot_sort_value := authority.simple_heading_find_pivot(atag_list,q,thesauruses);

    IF page < 0 THEN
        RETURN QUERY
            -- "bottom" half of the browse results
            SELECT id FROM (
                SELECT  ash.id,
                        row_number() over ()
                  FROM  authority.simple_heading ash
                  WHERE ash.atag = ANY (atag_list)
                        AND CASE thesauruses
                            WHEN '' THEN TRUE
                            ELSE ash.thesaurus = ANY(regexp_split_to_array(thesauruses, ','))
                            END
                        AND ash.sort_value < pivot_sort_value
                  ORDER BY ash.sort_value DESC
                  LIMIT pagesize
                  OFFSET (ABS(page) - 1) * pagesize
            ) x ORDER BY row_number DESC;
    END IF;

    IF page >= 0 THEN
        RETURN QUERY
            -- "bottom" half of the browse results
            SELECT  ash.id
              FROM  authority.simple_heading ash
              WHERE ash.atag = ANY (atag_list)
                AND CASE thesauruses
                    WHEN '' THEN TRUE
                    ELSE ash.thesaurus = ANY(regexp_split_to_array(thesauruses, ','))
                    END
                    AND ash.sort_value >= pivot_sort_value
              ORDER BY ash.sort_value
              LIMIT pagesize
              OFFSET ABS(page) * pagesize ;
    END IF;
END;
$$ LANGUAGE PLPGSQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_browse_top( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.axis_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_browse_top( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.btag_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_browse_top( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.atag_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_browse_top_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.axis_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_browse_top_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.btag_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_browse_top_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.atag_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;


CREATE OR REPLACE FUNCTION authority.simple_heading_search_rank( atag_list INT[], q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT  ash.id
      FROM  authority.simple_heading ash,
            public.naco_normalize($2) t(term),
            plainto_tsquery('keyword'::regconfig,$2) ptsq(term)
      WHERE ash.atag = ANY ($1)
            AND ash.index_vector @@ ptsq.term
            AND CASE $5
                WHEN '' THEN TRUE
                ELSE ash.thesaurus = ANY(regexp_split_to_array($5, ','))
                END
      ORDER BY ts_rank_cd(ash.index_vector,ptsq.term,14)::numeric
                    + CASE WHEN ash.sort_value LIKE t.term || '%' THEN 2 ELSE 0 END
                    + CASE WHEN ash.value LIKE t.term || '%' THEN 1 ELSE 0 END DESC
      LIMIT $4
      OFFSET $4 * $3;
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_search_rank( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.axis_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_search_rank( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.btag_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_search_rank( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.atag_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_search_rank_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.axis_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_search_rank_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.btag_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_search_rank_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.atag_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;


CREATE OR REPLACE FUNCTION authority.simple_heading_search_heading( atag_list INT[], q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT  ash.id
      FROM  authority.simple_heading ash,
            public.naco_normalize($2) t(term),
            plainto_tsquery('keyword'::regconfig,$2) ptsq(term)
      WHERE ash.atag = ANY ($1)
            AND ash.index_vector @@ ptsq.term
            AND CASE $5
                WHEN '' THEN TRUE
                ELSE ash.thesaurus = ANY(regexp_split_to_array($5, ','))
                END
      ORDER BY ash.sort_value
      LIMIT $4
      OFFSET $4 * $3;
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_search_heading( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.axis_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_search_heading( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.btag_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_search_heading( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.atag_authority_tags($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_search_heading_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.axis_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_search_heading_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.btag_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_search_heading_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10, thesauruses TEXT DEFAULT '' ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.atag_authority_tags_refs($1), $2, $3, $4, $5)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.extract_headings(marc TEXT, restrict INT[] DEFAULT NULL) RETURNS SETOF authority.heading AS $func$
DECLARE
    idx         authority.heading_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    heading_node    TEXT;
    heading_node_list   TEXT[];
    component_node    TEXT;
    component_node_list   TEXT[];
    raw_text    TEXT;
    normalized_text    TEXT;
    normalizer  RECORD;
    curr_text   TEXT;
    joiner      TEXT;
    type_value  TEXT;
    base_thesaurus TEXT := NULL;
    output_row  authority.heading;
BEGIN

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM authority.heading_field WHERE restrict IS NULL OR id = ANY (restrict) ORDER BY format LOOP

        output_row.field   := idx.id;
        output_row.type    := idx.heading_type;
        output_row.purpose := idx.heading_purpose;

        joiner := COALESCE(idx.joiner, ' ');

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(marc, xfrm.xslt);
            ELSE
                transformed_xml := marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        IF idx.thesaurus_xpath IS NOT NULL THEN
            base_thesaurus := ARRAY_TO_STRING(oils_xpath(idx.thesaurus_xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
        END IF;

        heading_node_list := oils_xpath( idx.heading_xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        FOR heading_node IN SELECT x FROM unnest(heading_node_list) AS x LOOP

            CONTINUE WHEN heading_node !~ E'^\\s*<';

            output_row.variant_type := NULL;
            output_row.related_type := NULL;
            output_row.thesaurus    := NULL;
            output_row.heading      := NULL;

            IF idx.heading_purpose = 'variant' AND idx.type_xpath IS NOT NULL THEN
                type_value := ARRAY_TO_STRING(oils_xpath(idx.type_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
                BEGIN
                    output_row.variant_type := type_value;
                EXCEPTION WHEN invalid_text_representation THEN
                    RAISE NOTICE 'Do not recognize variant heading type %', type_value;
                END;
            END IF;
            IF idx.heading_purpose = 'related' AND idx.type_xpath IS NOT NULL THEN
                type_value := ARRAY_TO_STRING(oils_xpath(idx.type_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
                BEGIN
                    output_row.related_type := type_value;
                EXCEPTION WHEN invalid_text_representation THEN
                    RAISE NOTICE 'Do not recognize related heading type %', type_value;
                END;
            END IF;
 
            IF idx.thesaurus_override_xpath IS NOT NULL THEN
                output_row.thesaurus := ARRAY_TO_STRING(oils_xpath(idx.thesaurus_override_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
            END IF;
            IF output_row.thesaurus IS NULL THEN
                output_row.thesaurus := base_thesaurus;
            END IF;

            raw_text := NULL;

            -- now iterate over components of heading
            component_node_list := oils_xpath( idx.component_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
            FOR component_node IN SELECT x FROM unnest(component_node_list) AS x LOOP
            -- XXX much of this should be moved into oils_xpath_string...
                curr_text := ARRAY_TO_STRING(array_remove(array_remove(
                    oils_xpath( '//text()', -- get the content of all the nodes within the main selected node
                        REGEXP_REPLACE( component_node, E'\\s+', ' ', 'g' ) -- Translate adjacent whitespace to a single space
                    ), ' '), ''),  -- throw away morally empty (bankrupt?) strings
                    joiner
                );

                CONTINUE WHEN curr_text IS NULL OR curr_text = '';

                IF raw_text IS NOT NULL THEN
                    raw_text := raw_text || joiner;
                END IF;

                raw_text := COALESCE(raw_text,'') || curr_text;
            END LOOP;

            IF raw_text IS NOT NULL THEN
                output_row.heading := raw_text;
                normalized_text := raw_text;

                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                    FROM  config.index_normalizer n
                            JOIN authority.heading_field_norm_map m ON (m.norm = n.id)
                    WHERE m.field = idx.id
                    ORDER BY m.pos LOOP
            
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            quote_literal( normalized_text ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO normalized_text;
            
                END LOOP;
            
                output_row.normalized_heading := normalized_text;
            
                RETURN NEXT output_row;
            END IF;
        END LOOP;

    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.extract_headings(rid BIGINT, restrict INT[] DEFAULT NULL) RETURNS SETOF authority.heading AS $func$
DECLARE
    auth        authority.record_entry%ROWTYPE;
    output_row  authority.heading;
BEGIN
    -- Get the record
    SELECT INTO auth * FROM authority.record_entry WHERE id = rid;

    RETURN QUERY SELECT * FROM authority.extract_headings(auth.marc, restrict);
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

