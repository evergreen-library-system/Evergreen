/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
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

DROP SCHEMA IF EXISTS metabib CASCADE;

BEGIN;
CREATE SCHEMA metabib;

CREATE TABLE metabib.metarecord (
	id		BIGSERIAL	PRIMARY KEY,
	fingerprint	TEXT		NOT NULL,
	master_record	BIGINT,
	mods		TEXT
);
CREATE INDEX metabib_metarecord_master_record_idx ON metabib.metarecord (master_record);
CREATE INDEX metabib_metarecord_fingerprint_idx ON metabib.metarecord (fingerprint);

CREATE TABLE metabib.identifier_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_identifier_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.identifier_field_entry
	FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('identifier');

CREATE INDEX metabib_identifier_field_entry_index_vector_idx ON metabib.identifier_field_entry USING GIST (index_vector);
CREATE INDEX metabib_identifier_field_entry_value_idx ON metabib.identifier_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_identifier_field_entry_source_idx ON metabib.identifier_field_entry (source);

CREATE TABLE metabib.combined_identifier_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_identifier_field_entry_fakepk_idx ON metabib.combined_identifier_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_identifier_field_entry_index_vector_idx ON metabib.combined_identifier_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_identifier_field_source_idx ON metabib.combined_identifier_field_entry (metabib_field);

CREATE TABLE metabib.title_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_title_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.title_field_entry
	FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('title');

CREATE INDEX metabib_title_field_entry_index_vector_idx ON metabib.title_field_entry USING GIST (index_vector);
CREATE INDEX metabib_title_field_entry_value_idx ON metabib.title_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_title_field_entry_source_idx ON metabib.title_field_entry (source);

CREATE TABLE metabib.combined_title_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_title_field_entry_fakepk_idx ON metabib.combined_title_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_title_field_entry_index_vector_idx ON metabib.combined_title_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_title_field_source_idx ON metabib.combined_title_field_entry (metabib_field);

CREATE TABLE metabib.author_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_author_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.author_field_entry
	FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('author');

CREATE INDEX metabib_author_field_entry_index_vector_idx ON metabib.author_field_entry USING GIST (index_vector);
CREATE INDEX metabib_author_field_entry_value_idx ON metabib.author_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_author_field_entry_source_idx ON metabib.author_field_entry (source);

CREATE TABLE metabib.combined_author_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_author_field_entry_fakepk_idx ON metabib.combined_author_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_author_field_entry_index_vector_idx ON metabib.combined_author_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_author_field_source_idx ON metabib.combined_author_field_entry (metabib_field);

CREATE TABLE metabib.subject_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_subject_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.subject_field_entry
	FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('subject');

CREATE INDEX metabib_subject_field_entry_index_vector_idx ON metabib.subject_field_entry USING GIST (index_vector);
CREATE INDEX metabib_subject_field_entry_value_idx ON metabib.subject_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_subject_field_entry_source_idx ON metabib.subject_field_entry (source);

CREATE TABLE metabib.combined_subject_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_subject_field_entry_fakepk_idx ON metabib.combined_subject_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_subject_field_entry_index_vector_idx ON metabib.combined_subject_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_subject_field_source_idx ON metabib.combined_subject_field_entry (metabib_field);

CREATE TABLE metabib.keyword_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_keyword_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.keyword_field_entry
	FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE INDEX metabib_keyword_field_entry_index_vector_idx ON metabib.keyword_field_entry USING GIST (index_vector);
CREATE INDEX metabib_keyword_field_entry_value_idx ON metabib.keyword_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_keyword_field_entry_source_idx ON metabib.keyword_field_entry (source);

CREATE TABLE metabib.combined_keyword_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_keyword_field_entry_fakepk_idx ON metabib.combined_keyword_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_keyword_field_entry_index_vector_idx ON metabib.combined_keyword_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_keyword_field_source_idx ON metabib.combined_keyword_field_entry (metabib_field);

CREATE TABLE metabib.series_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_series_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.series_field_entry
	FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('series');

CREATE INDEX metabib_series_field_entry_index_vector_idx ON metabib.series_field_entry USING GIST (index_vector);
CREATE INDEX metabib_series_field_entry_value_idx ON metabib.series_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_series_field_entry_source_idx ON metabib.series_field_entry (source);

CREATE TABLE metabib.combined_series_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_series_field_entry_fakepk_idx ON metabib.combined_series_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_series_field_entry_index_vector_idx ON metabib.combined_series_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_series_field_source_idx ON metabib.combined_series_field_entry (metabib_field);

CREATE TABLE metabib.facet_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL
);
CREATE INDEX metabib_facet_entry_field_idx ON metabib.facet_entry (field);
CREATE INDEX metabib_facet_entry_value_idx ON metabib.facet_entry (SUBSTRING(value,1,1024));
CREATE INDEX metabib_facet_entry_source_idx ON metabib.facet_entry (source);

CREATE TABLE metabib.browse_entry (
    id BIGSERIAL PRIMARY KEY,
    value TEXT,
    index_vector tsvector,
    sort_value  TEXT NOT NULL,
    UNIQUE(sort_value, value)
);


CREATE INDEX browse_entry_sort_value_idx
    ON metabib.browse_entry USING BTREE (sort_value);

CREATE INDEX metabib_browse_entry_index_vector_idx ON metabib.browse_entry USING GIN (index_vector);
CREATE TRIGGER metabib_browse_entry_fti_trigger
    BEFORE INSERT OR UPDATE ON metabib.browse_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');


CREATE TABLE metabib.browse_entry_def_map (
    id BIGSERIAL PRIMARY KEY,
    entry BIGINT REFERENCES metabib.browse_entry (id),
    def INT REFERENCES config.metabib_field (id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    source BIGINT REFERENCES biblio.record_entry (id),
    authority BIGINT REFERENCES authority.record_entry (id) ON DELETE SET NULL
);
CREATE INDEX browse_entry_def_map_def_idx ON metabib.browse_entry_def_map (def);
CREATE INDEX browse_entry_def_map_entry_idx ON metabib.browse_entry_def_map (entry);
CREATE INDEX browse_entry_def_map_source_idx ON metabib.browse_entry_def_map (source);

CREATE TABLE metabib.browse_entry_simple_heading_map (
    id BIGSERIAL PRIMARY KEY,
    entry BIGINT REFERENCES metabib.browse_entry (id),
    simple_heading BIGINT REFERENCES authority.simple_heading (id) ON DELETE CASCADE
);
CREATE INDEX browse_entry_sh_map_entry_idx ON metabib.browse_entry_simple_heading_map (entry);
CREATE INDEX browse_entry_sh_map_sh_idx ON metabib.browse_entry_simple_heading_map (simple_heading);

CREATE OR REPLACE FUNCTION metabib.facet_normalize_trigger () RETURNS TRIGGER AS $$
DECLARE
    normalizer  RECORD;
    facet_text  TEXT;
BEGIN
    facet_text := NEW.value;

    FOR normalizer IN
        SELECT  n.func AS func,
                n.param_count AS param_count,
                m.params AS params
          FROM  config.index_normalizer n
                JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
          WHERE m.field = NEW.field AND m.pos < 0
          ORDER BY m.pos LOOP

            EXECUTE 'SELECT ' || normalizer.func || '(' ||
                quote_literal( facet_text ) ||
                CASE
                    WHEN normalizer.param_count > 0
                        THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                        ELSE ''
                    END ||
                ')' INTO facet_text;

    END LOOP;

    NEW.value = facet_text;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER facet_normalize_tgr
	BEFORE UPDATE OR INSERT ON metabib.facet_entry
	FOR EACH ROW EXECUTE PROCEDURE metabib.facet_normalize_trigger();

CREATE OR REPLACE FUNCTION evergreen.facet_force_nfc() RETURNS TRIGGER AS $$
BEGIN
    NEW.value := force_unicode_normal_form(NEW.value,'NFC');
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER facet_force_nfc_tgr
	BEFORE UPDATE OR INSERT ON metabib.facet_entry
	FOR EACH ROW EXECUTE PROCEDURE evergreen.facet_force_nfc();

-- DECREMENTING serial starts at -1
CREATE SEQUENCE metabib.uncontrolled_record_attr_value_id_seq INCREMENT BY -1;

CREATE TABLE metabib.uncontrolled_record_attr_value (
    id      BIGINT  PRIMARY KEY DEFAULT nextval('metabib.uncontrolled_record_attr_value_id_seq'),
    attr    TEXT    NOT NULL REFERENCES config.record_attr_definition (name),
    value   TEXT    NOT NULL
);
CREATE UNIQUE INDEX muv_once_idx ON metabib.uncontrolled_record_attr_value (attr,value);

CREATE VIEW metabib.record_attr_id_map AS
    SELECT id, attr, value FROM metabib.uncontrolled_record_attr_value
        UNION
    SELECT  c.id, c.ctype AS attr, c.code AS value
      FROM  config.coded_value_map c
            JOIN config.record_attr_definition d ON (d.name = c.ctype AND NOT d.composite);

CREATE VIEW metabib.composite_attr_id_map AS
    SELECT  c.id, c.ctype AS attr, c.code AS value
      FROM  config.coded_value_map c
            JOIN config.record_attr_definition d ON (d.name = c.ctype AND d.composite);

CREATE VIEW metabib.full_attr_id_map AS
    SELECT id, attr, value FROM metabib.record_attr_id_map
        UNION
    SELECT id, attr, value FROM metabib.composite_attr_id_map;


CREATE OR REPLACE FUNCTION metabib.compile_composite_attr_cache_init () RETURNS BOOL AS $f$
    $_SHARED{metabib_compile_composite_attr_cache} = {}
        if ! exists $_SHARED{metabib_compile_composite_attr_cache};
    return exists $_SHARED{metabib_compile_composite_attr_cache};
$f$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr_cache_disable () RETURNS BOOL AS $f$
    delete $_SHARED{metabib_compile_composite_attr_cache};
    return ! exists $_SHARED{metabib_compile_composite_attr_cache};
$f$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr_cache_invalidate () RETURNS BOOL AS $f$
    SELECT metabib.compile_composite_attr_cache_disable() AND metabib.compile_composite_attr_cache_init();
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.composite_attr_def_cache_inval_tgr () RETURNS TRIGGER AS $f$
BEGIN
    PERFORM metabib.compile_composite_attr_cache_invalidate();
    RETURN NULL;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER ccraed_cache_inval_tgr AFTER INSERT OR UPDATE OR DELETE ON config.composite_attr_entry_definition FOR EACH STATEMENT EXECUTE PROCEDURE metabib.composite_attr_def_cache_inval_tgr();
    
CREATE OR REPLACE FUNCTION metabib.compile_composite_attr ( cattr_def TEXT ) RETURNS query_int AS $func$

    use JSON::XS;

    my $json = shift;
    my $def = decode_json($json);

    die("Composite attribute definition not supplied") unless $def;

    my $_cache = (exists $_SHARED{metabib_compile_composite_attr_cache}) ? 1 : 0;

    return $_SHARED{metabib_compile_composite_attr_cache}{$json}
        if ($_cache && $_SHARED{metabib_compile_composite_attr_cache}{$json});

    sub recurse {
        my $d = shift;
        my $j = '&';
        my @list;

        if (ref $d eq 'HASH') { # node or AND
            if (exists $d->{_attr}) { # it is a node
                my $plan = spi_prepare('SELECT * FROM metabib.full_attr_id_map WHERE attr = $1 AND value = $2', qw/TEXT TEXT/);
                my $id = spi_exec_prepared(
                    $plan, {limit => 1}, $d->{_attr}, $d->{_val}
                )->{rows}[0]{id};
                spi_freeplan($plan);
                return $id;
            } elsif (exists $d->{_not} && scalar(keys(%$d)) == 1) { # it is a NOT
                return '!' . recurse($$d{_not});
            } else { # an AND list
                @list = map { recurse($$d{$_}) } sort keys %$d;
            }
        } elsif (ref $d eq 'ARRAY') {
            $j = '|';
            @list = map { recurse($_) } @$d;
        }

        @list = grep { defined && $_ ne '' } @list;

        return '(' . join($j,@list) . ')' if @list;
        return '';
    }

    my $val = recurse($def) || undef;
    $_SHARED{metabib_compile_composite_attr_cache}{$json} = $val if $_cache;
    return $val;

$func$ IMMUTABLE LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr ( cattr_id INT ) RETURNS query_int AS $func$
    SELECT metabib.compile_composite_attr(definition) FROM config.composite_attr_entry_definition WHERE coded_value = $1;
$func$ STRICT IMMUTABLE LANGUAGE SQL;

CREATE TABLE metabib.record_attr_vector_list (
    source  BIGINT  PRIMARY KEY REFERENCES biblio.record_entry (id),
    vlist   INT[]   NOT NULL -- stores id from ccvm AND murav
);
CREATE INDEX mrca_vlist_idx ON metabib.record_attr_vector_list USING gin ( vlist gin__int_ops );

/* This becomes a view, and we do sorters differently ...
CREATE TABLE metabib.record_attr (
	id		BIGINT	PRIMARY KEY REFERENCES biblio.record_entry (id) ON DELETE CASCADE,
	attrs	HSTORE	NOT NULL DEFAULT ''::HSTORE
);
CREATE INDEX metabib_svf_attrs_idx ON metabib.record_attr USING GIST (attrs);
CREATE INDEX metabib_svf_date1_idx ON metabib.record_attr ((attrs->'date1'));
CREATE INDEX metabib_svf_dates_idx ON metabib.record_attr ((attrs->'date1'),(attrs->'date2'));
*/

/* ... like this */
CREATE TABLE metabib.record_sorter (
    id      BIGSERIAL   PRIMARY KEY,
    source  BIGINT      NOT NULL REFERENCES biblio.record_entry (id) ON DELETE CASCADE,
    attr    TEXT        NOT NULL REFERENCES config.record_attr_definition (name) ON DELETE CASCADE,
    value   TEXT        NOT NULL
);
CREATE INDEX metabib_sorter_source_idx ON metabib.record_sorter (source); -- we may not need one of this or the next ... stats will tell
CREATE INDEX metabib_sorter_s_a_idx ON metabib.record_sorter (source, attr);
CREATE INDEX metabib_sorter_a_v_idx ON metabib.record_sorter (attr, value);


CREATE TYPE metabib.record_attr_type AS (
    id      BIGINT,
    attrs   HSTORE
);

-- Back-compat view ... we're moving to an INTARRAY world
CREATE VIEW metabib.record_attr_flat AS
    SELECT  v.source AS id,
            m.attr AS attr,
            m.value AS value
      FROM  metabib.record_attr_vector_list v
            LEFT JOIN metabib.uncontrolled_record_attr_value m ON ( m.id = ANY( v.vlist ) )
        UNION
    SELECT  v.source AS id,
            c.ctype AS attr,
            c.code AS value
      FROM  metabib.record_attr_vector_list v
            LEFT JOIN config.coded_value_map c ON ( c.id = ANY( v.vlist ) );

CREATE VIEW metabib.record_attr AS
    SELECT  id, HSTORE( ARRAY_AGG( attr ), ARRAY_AGG( value ) ) AS attrs
      FROM  metabib.record_attr_flat
      WHERE attr IS NOT NULL
      GROUP BY 1;

-- Back-back-compat view ... we use to live in an HSTORE world
CREATE TYPE metabib.rec_desc_type AS (
    item_type       TEXT,
    item_form       TEXT,
    bib_level       TEXT,
    control_type    TEXT,
    char_encoding   TEXT,
    enc_level       TEXT,
    audience        TEXT,
    lit_form        TEXT,
    type_mat        TEXT,
    cat_form        TEXT,
    pub_status      TEXT,
    item_lang       TEXT,
    vr_format       TEXT,
    date1           TEXT,
    date2           TEXT
);

CREATE VIEW metabib.rec_descriptor AS
    SELECT  id,
            id AS record,
            (populate_record(NULL::metabib.rec_desc_type, attrs)).*
      FROM  metabib.record_attr;

-- Use a sequence that matches previous version, for easier upgrading.
CREATE SEQUENCE metabib.full_rec_id_seq;

CREATE TABLE metabib.real_full_rec (
	id		    BIGINT	NOT NULL DEFAULT NEXTVAL('metabib.full_rec_id_seq'::REGCLASS),
	record		BIGINT		NOT NULL,
	tag		CHAR(3)		NOT NULL,
	ind1		TEXT,
	ind2		TEXT,
	subfield	TEXT,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
ALTER TABLE metabib.real_full_rec ADD PRIMARY KEY (id);

CREATE INDEX metabib_full_rec_tag_subfield_idx ON metabib.real_full_rec (tag,subfield);
CREATE INDEX metabib_full_rec_value_idx ON metabib.real_full_rec (substring(value,1,1024));
/* Enable LIKE to use an index for database clusters with locales other than C or POSIX */
CREATE INDEX metabib_full_rec_value_tpo_index ON metabib.real_full_rec (substring(value,1,1024) text_pattern_ops);
CREATE INDEX metabib_full_rec_record_idx ON metabib.real_full_rec (record);
CREATE INDEX metabib_full_rec_index_vector_idx ON metabib.real_full_rec USING GIST (index_vector);
CREATE INDEX metabib_full_rec_isxn_caseless_idx
    ON metabib.real_full_rec (LOWER(value))
    WHERE tag IN ('020', '022', '024');
-- This next index might fully supplant the one above, but leaving both for now.
-- (they are not too large)
-- The reason we need this index is to ensure that the query parser always
-- prefers this index over the simpler tag/subfield index, as this greatly
-- increases Vandelay overlay speed for these identifiers, especially when
-- a record has many of these fields (around > 4-6 seems like the cutoff
-- on at least one PG9.1 system)
-- A similar index could be added for other fields (e.g. 010), but one should
-- leave out the LOWER() in all other cases.
-- TODO: verify whether we can discard the non tag/subfield/substring version
-- above (metabib_full_rec_isxn_caseless_idx)
CREATE INDEX metabib_full_rec_02x_tag_subfield_lower_substring
    ON metabib.real_full_rec (tag, subfield, LOWER(substring(value, 1, 1024)))
    WHERE tag IN ('020', '022', '024');


CREATE TRIGGER metabib_full_rec_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.real_full_rec
	FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('default');

CREATE OR REPLACE VIEW metabib.full_rec AS
    SELECT  id,
            record,
            tag,
            ind1,
            ind2,
            subfield,
            SUBSTRING(value,1,1024) AS value,
            index_vector
      FROM  metabib.real_full_rec;

CREATE OR REPLACE RULE metabib_full_rec_insert_rule
    AS ON INSERT TO metabib.full_rec
    DO INSTEAD
    INSERT INTO metabib.real_full_rec VALUES (
        COALESCE(NEW.id, NEXTVAL('metabib.full_rec_id_seq'::REGCLASS)),
        NEW.record,
        NEW.tag,
        NEW.ind1,
        NEW.ind2,
        NEW.subfield,
        NEW.value,
        NEW.index_vector
    );

CREATE OR REPLACE RULE metabib_full_rec_update_rule
    AS ON UPDATE TO metabib.full_rec
    DO INSTEAD
    UPDATE  metabib.real_full_rec SET
        id = NEW.id,
        record = NEW.record,
        tag = NEW.tag,
        ind1 = NEW.ind1,
        ind2 = NEW.ind2,
        subfield = NEW.subfield,
        value = NEW.value,
        index_vector = NEW.index_vector
      WHERE id = OLD.id;

CREATE OR REPLACE RULE metabib_full_rec_delete_rule
    AS ON DELETE TO metabib.full_rec
    DO INSTEAD
    DELETE FROM metabib.real_full_rec WHERE id = OLD.id;

CREATE TABLE metabib.metarecord_source_map (
	id		BIGSERIAL	PRIMARY KEY,
	metarecord	BIGINT		NOT NULL,
	source		BIGINT		NOT NULL
);
CREATE INDEX metabib_metarecord_source_map_metarecord_idx ON metabib.metarecord_source_map (metarecord);
CREATE INDEX metabib_metarecord_source_map_source_record_idx ON metabib.metarecord_source_map (source);

CREATE TYPE metabib.field_entry_template AS (
    field_class         TEXT,
    field               INT,
    facet_field         BOOL,
    search_field        BOOL,
    browse_field        BOOL,
    source              BIGINT,
    value               TEXT,
    authority           BIGINT,
    sort_value          TEXT
);


CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( rid BIGINT, default_joiner TEXT ) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    browse_text TEXT;
    sort_value  TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    authority_text TEXT;
    authority_link BIGINT;
    output_row  metabib.field_entry_template%ROWTYPE;
BEGIN

    -- Start out with no field-use bools set
    output_row.browse_field = FALSE;
    output_row.facet_field = FALSE;
    output_row.search_field = FALSE;

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field ORDER BY format LOOP

        joiner := COALESCE(idx.joiner, default_joiner);

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(bib.marc,xfrm.xslt);
            ELSE
                transformed_xml := bib.marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        raw_text := NULL;
        FOR xml_node IN SELECT x FROM unnest(xml_node_list) AS x LOOP
            CONTINUE WHEN xml_node !~ E'^\\s*<';

            -- XXX much of this should be moved into oils_xpath_string...
            curr_text := ARRAY_TO_STRING(evergreen.array_remove_item_by_value(evergreen.array_remove_item_by_value(
                oils_xpath( '//text()', -- get the content of all the nodes within the main selected node
                    REGEXP_REPLACE( xml_node, E'\\s+', ' ', 'g' ) -- Translate adjacent whitespace to a single space
                ), ' '), ''),  -- throw away morally empty (bankrupt?) strings
                joiner
            );

            CONTINUE WHEN curr_text IS NULL OR curr_text = '';

            IF raw_text IS NOT NULL THEN
                raw_text := raw_text || joiner;
            END IF;

            raw_text := COALESCE(raw_text,'') || curr_text;

            -- autosuggest/metabib.browse_entry
            IF idx.browse_field THEN

                IF idx.browse_xpath IS NOT NULL AND idx.browse_xpath <> '' THEN
                    browse_text := oils_xpath_string( idx.browse_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    browse_text := curr_text;
                END IF;

                IF idx.browse_sort_xpath IS NOT NULL AND
                    idx.browse_sort_xpath <> '' THEN

                    sort_value := oils_xpath_string(
                        idx.browse_sort_xpath, xml_node, joiner,
                        ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                    );
                ELSE
                    sort_value := browse_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(browse_text, E'\\s+', ' ', 'g'));
                output_row.sort_value :=
                    public.naco_normalize(sort_value);

                output_row.authority := NULL;

                IF idx.authority_xpath IS NOT NULL AND idx.authority_xpath <> '' THEN
                    authority_text := oils_xpath_string(
                        idx.authority_xpath, xml_node, joiner,
                        ARRAY[
                            ARRAY[xfrm.prefix, xfrm.namespace_uri],
                            ARRAY['xlink','http://www.w3.org/1999/xlink']
                        ]
                    );

                    IF authority_text ~ '^\d+$' THEN
                        authority_link := authority_text::BIGINT;
                        PERFORM * FROM authority.record_entry WHERE id = authority_link;
                        IF FOUND THEN
                            output_row.authority := authority_link;
                        END IF;
                    END IF;

                END IF;

                output_row.browse_field = TRUE;
                -- Returning browse rows with search_field = true for search+browse
                -- configs allows us to retain granularity of being able to search
                -- browse fields with "starts with" type operators (for example, for
                -- titles of songs in music albums)
                IF idx.search_field THEN
                    output_row.search_field = TRUE;
                END IF;
                RETURN NEXT output_row;
                output_row.browse_field = FALSE;
                output_row.search_field = FALSE;
                output_row.sort_value := NULL;
            END IF;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                IF idx.facet_xpath IS NOT NULL AND idx.facet_xpath <> '' THEN
                    facet_text := oils_xpath_string( idx.facet_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    facet_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(facet_text, E'\\s+', ' ', 'g'));

                output_row.facet_field = TRUE;
                RETURN NEXT output_row;
                output_row.facet_field = FALSE;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            output_row.search_field = TRUE;
            RETURN NEXT output_row;
            output_row.search_field = FALSE;
        END IF;

    END LOOP;

END;

$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.update_combined_index_vectors(bib_id BIGINT) RETURNS VOID AS $func$
BEGIN
    DELETE FROM metabib.combined_keyword_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_keyword_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.keyword_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_keyword_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.keyword_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_title_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_title_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.title_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_title_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.title_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_author_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_author_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.author_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_author_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.author_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_subject_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_subject_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.subject_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_subject_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.subject_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_series_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_series_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.series_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_series_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.series_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_identifier_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_identifier_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.identifier_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_identifier_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.identifier_field_entry WHERE source = bib_id;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT, skip_facet BOOL DEFAULT FALSE, skip_browse BOOL DEFAULT FALSE, skip_search BOOL DEFAULT FALSE ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    b_skip_facet    BOOL;
    b_skip_browse   BOOL;
    b_skip_search   BOOL;
    value_prepped   TEXT;
BEGIN

    SELECT COALESCE(NULLIF(skip_facet, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_facet_indexing' AND enabled)) INTO b_skip_facet;
    SELECT COALESCE(NULLIF(skip_browse, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_browse_indexing' AND enabled)) INTO b_skip_browse;
    SELECT COALESCE(NULLIF(skip_search, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_search_indexing' AND enabled)) INTO b_skip_search;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT b_skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP

	-- don't store what has been normalized away
        CONTINUE WHEN ind_data.value IS NULL;

        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT b_skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field AND NOT b_skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.

            CONTINUE WHEN ind_data.sort_value IS NULL;

            value_prepped := metabib.browse_normalize(ind_data.value, ind_data.field);
            SELECT INTO mbe_row * FROM metabib.browse_entry
                WHERE value = value_prepped AND sort_value = ind_data.sort_value;

            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry
                    ( value, sort_value ) VALUES
                    ( value_prepped, ind_data.sort_value );

                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source, authority)
                VALUES (mbe_id, ind_data.field, ind_data.source, ind_data.authority);
        END IF;

        IF ind_data.search_field AND NOT b_skip_search THEN
            -- Avoid inserting duplicate rows
            EXECUTE 'SELECT 1 FROM metabib.' || ind_data.field_class ||
                '_field_entry WHERE field = $1 AND source = $2 AND value = $3'
                INTO mbe_id USING ind_data.field, ind_data.source, ind_data.value;
                -- RAISE NOTICE 'Search for an already matching row returned %', mbe_id;
            IF mbe_id IS NULL THEN
                EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
            END IF;
        END IF;

    END LOOP;

    IF NOT b_skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- default to a space joiner
CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( BIGINT ) RETURNS SETOF metabib.field_entry_template AS $func$
	SELECT * FROM biblio.extract_metabib_field_entry($1, ' ');
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.flatten_marc ( rid BIGINT ) RETURNS SETOF authority.full_rec AS $func$
DECLARE
	auth	authority.record_entry%ROWTYPE;
	output	authority.full_rec%ROWTYPE;
	field	RECORD;
BEGIN
	SELECT INTO auth * FROM authority.record_entry WHERE id = rid;

	FOR field IN SELECT * FROM vandelay.flatten_marc( auth.marc ) LOOP
		output.record := rid;
		output.ind1 := field.ind1;
		output.ind2 := field.ind2;
		output.tag := field.tag;
		output.subfield := field.subfield;
		output.value := field.value;

		RETURN NEXT output;
	END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.flatten_marc ( rid BIGINT ) RETURNS SETOF metabib.full_rec AS $func$
DECLARE
	bib	biblio.record_entry%ROWTYPE;
	output	metabib.full_rec%ROWTYPE;
	field	RECORD;
BEGIN
	SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

	FOR field IN SELECT * FROM vandelay.flatten_marc( bib.marc ) LOOP
		output.record := rid;
		output.ind1 := field.ind1;
		output.ind2 := field.ind2;
		output.tag := field.tag;
		output.subfield := field.subfield;
		output.value := field.value;

		RETURN NEXT output;
	END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_fixed_field_list( rid BIGINT, ff TEXT ) RETURNS TEXT[] AS $func$
    SELECT * FROM vandelay.marc21_extract_fixed_field_list( (SELECT marc FROM biblio.record_entry WHERE id = $1), $2, TRUE );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_fixed_field( rid BIGINT, ff TEXT ) RETURNS TEXT AS $func$
    SELECT * FROM vandelay.marc21_extract_fixed_field( (SELECT marc FROM biblio.record_entry WHERE id = $1), $2, TRUE );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_all_fixed_fields( rid BIGINT ) RETURNS SETOF biblio.record_ff_map AS $func$
    SELECT $1 AS record, ff_name, ff_value FROM vandelay.marc21_extract_all_fixed_fields( (SELECT marc FROM biblio.record_entry WHERE id = $1), TRUE );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION biblio.marc21_physical_characteristics( rid BIGINT ) RETURNS SETOF biblio.marc21_physical_characteristics AS $func$
    SELECT id, $1 AS record, ptype, subfield, value FROM vandelay.marc21_physical_characteristics( (SELECT marc FROM biblio.record_entry WHERE id = $1) );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION biblio.extract_quality ( marc TEXT, best_lang TEXT, best_type TEXT ) RETURNS INT AS $func$
DECLARE
    qual        INT;
    ldr         TEXT;
    tval        TEXT;
    tval_rec    RECORD;
    bval        TEXT;
    bval_rec    RECORD;
    type_map    RECORD;
    ff_pos      RECORD;
    ff_tag_data TEXT;
BEGIN

    IF marc IS NULL OR marc = '' THEN
        RETURN NULL;
    END IF;

    -- First, the count of tags
    qual := ARRAY_UPPER(oils_xpath('*[local-name()="datafield"]', marc), 1);

    -- now go through a bunch of pain to get the record type
    IF best_type IS NOT NULL THEN
        ldr := (oils_xpath('//*[local-name()="leader"]/text()', marc))[1];

        IF ldr IS NOT NULL THEN
            SELECT * INTO tval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'Type' LIMIT 1; -- They're all the same
            SELECT * INTO bval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'BLvl' LIMIT 1; -- They're all the same


            tval := SUBSTRING( ldr, tval_rec.start_pos + 1, tval_rec.length );
            bval := SUBSTRING( ldr, bval_rec.start_pos + 1, bval_rec.length );

            -- RAISE NOTICE 'type %, blvl %, ldr %', tval, bval, ldr;

            SELECT * INTO type_map FROM config.marc21_rec_type_map WHERE type_val LIKE '%' || tval || '%' AND blvl_val LIKE '%' || bval || '%';

            IF type_map.code IS NOT NULL THEN
                IF best_type = type_map.code THEN
                    qual := qual + qual / 2;
                END IF;

                FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = 'Lang' AND rec_type = type_map.code ORDER BY tag DESC LOOP
                    ff_tag_data := SUBSTRING((oils_xpath('//*[@tag="' || ff_pos.tag || '"]/text()',marc))[1], ff_pos.start_pos + 1, ff_pos.length);
                    IF ff_tag_data = best_lang THEN
                            qual := qual + 100;
                    END IF;
                END LOOP;
            END IF;
        END IF;
    END IF;

    -- Now look for some quality metrics
    -- DCL record?
    IF ARRAY_UPPER(oils_xpath('//*[@tag="040"]/*[@code="a" and contains(.,"DLC")]', marc), 1) = 1 THEN
        qual := qual + 10;
    END IF;

    -- From OCLC?
    IF (oils_xpath('//*[@tag="003"]/text()', marc))[1] ~* E'oclo?c' THEN
        qual := qual + 10;
    END IF;

    RETURN qual;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.extract_fingerprint ( marc text ) RETURNS TEXT AS $func$
DECLARE
	idx		config.biblio_fingerprint%ROWTYPE;
	xfrm		config.xml_transform%ROWTYPE;
	prev_xfrm	TEXT;
	transformed_xml	TEXT;
	xml_node	TEXT;
	xml_node_list	TEXT[];
	raw_text	TEXT;
    output_text TEXT := '';
BEGIN

    IF marc IS NULL OR marc = '' THEN
        RETURN NULL;
    END IF;

	-- Loop over the indexing entries
	FOR idx IN SELECT * FROM config.biblio_fingerprint ORDER BY format, id LOOP

		SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

		-- See if we can skip the XSLT ... it's expensive
		IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
			-- Can't skip the transform
			IF xfrm.xslt <> '---' THEN
				transformed_xml := oils_xslt_process(marc,xfrm.xslt);
			ELSE
				transformed_xml := marc;
			END IF;

			prev_xfrm := xfrm.name;
		END IF;

		raw_text := COALESCE(
            naco_normalize(
                ARRAY_TO_STRING(
                    oils_xpath(
                        '//text()',
                        (oils_xpath(
                            idx.xpath,
                            transformed_xml,
                            ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] 
                        ))[1]
                    ),
                    ''
                )
            ),
            ''
        );

        raw_text := REGEXP_REPLACE(raw_text, E'\\[.+?\\]', E'');
        raw_text := REGEXP_REPLACE(raw_text, E'\\mthe\\M|\\man?d?d\\M', E'', 'g'); -- arg! the pain!

        IF idx.first_word IS TRUE THEN
            raw_text := REGEXP_REPLACE(raw_text, E'^(\\w+).*?$', E'\\1');
        END IF;

		output_text := output_text || idx.name || ':' ||
					   REGEXP_REPLACE(raw_text, E'\\s+', '', 'g') || ' ';

	END LOOP;

    RETURN BTRIM(output_text);

END;
$func$ LANGUAGE PLPGSQL;

-- BEFORE UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.fingerprint_trigger () RETURNS TRIGGER AS $func$
BEGIN

    -- For TG_ARGV, first param is language (like 'eng'), second is record type (like 'BKS')

    IF NEW.deleted IS TRUE THEN -- we don't much care, then, do we?
        RETURN NEW;
    END IF;

    NEW.fingerprint := biblio.extract_fingerprint(NEW.marc);
    NEW.quality := biblio.extract_quality(NEW.marc, TG_ARGV[0], TG_ARGV[1]);

    RETURN NEW;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_full_rec( bib_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        DELETE FROM metabib.real_full_rec WHERE record = bib_id;
    END IF;
    INSERT INTO metabib.real_full_rec (record, tag, ind1, ind2, subfield, value)
        SELECT record, tag, ind1, ind2, subfield, value FROM biblio.flatten_marc( bib_id );

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.extract_located_uris( bib_id BIGINT, marcxml TEXT, editor_id INT ) RETURNS VOID AS $func$
DECLARE
    uris            TEXT[];
    uri_xml         TEXT;
    uri_label       TEXT;
    uri_href        TEXT;
    uri_use         TEXT;
    uri_owner_list  TEXT[];
    uri_owner       TEXT;
    uri_owner_id    INT;
    uri_id          INT;
    uri_cn_id       INT;
    uri_map_id      INT;
BEGIN

    -- Clear any URI mappings and call numbers for this bib.
    -- This leads to acn / auricnm inflation, but also enables
    -- old acn/auricnm's to go away and for bibs to be deleted.
    FOR uri_cn_id IN SELECT id FROM asset.call_number WHERE record = bib_id AND label = '##URI##' AND NOT deleted LOOP
        DELETE FROM asset.uri_call_number_map WHERE call_number = uri_cn_id;
        DELETE FROM asset.call_number WHERE id = uri_cn_id;
    END LOOP;

    uris := oils_xpath('//*[@tag="856" and (@ind1="4" or @ind1="1") and (@ind2="0" or @ind2="1")]',marcxml);
    IF ARRAY_UPPER(uris,1) > 0 THEN
        FOR i IN 1 .. ARRAY_UPPER(uris, 1) LOOP
            -- First we pull info out of the 856
            uri_xml     := uris[i];

            uri_href    := (oils_xpath('//*[@code="u"]/text()',uri_xml))[1];
            uri_label   := (oils_xpath('//*[@code="y"]/text()|//*[@code="3"]/text()',uri_xml))[1];
            uri_use     := (oils_xpath('//*[@code="z"]/text()|//*[@code="2"]/text()|//*[@code="n"]/text()',uri_xml))[1];

            IF uri_label IS NULL THEN
                uri_label := uri_href;
            END IF;
            CONTINUE WHEN uri_href IS NULL;

            -- Get the distinct list of libraries wanting to use 
            SELECT  ARRAY_AGG(
                        DISTINCT REGEXP_REPLACE(
                            x,
                            $re$^.*?\((\w+)\).*$$re$,
                            E'\\1'
                        )
                    ) INTO uri_owner_list
              FROM  UNNEST(
                        oils_xpath(
                            '//*[@code="9"]/text()|//*[@code="w"]/text()|//*[@code="n"]/text()',
                            uri_xml
                        )
                    )x;

            IF ARRAY_UPPER(uri_owner_list,1) > 0 THEN

                -- look for a matching uri
                IF uri_use IS NULL THEN
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active;
                    END IF;
                ELSE
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
                    END IF;
                END IF;

                FOR j IN 1 .. ARRAY_UPPER(uri_owner_list, 1) LOOP
                    uri_owner := uri_owner_list[j];

                    SELECT id INTO uri_owner_id FROM actor.org_unit WHERE shortname = uri_owner;
                    CONTINUE WHEN NOT FOUND;

                    -- we need a call number to link through
                    SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    IF NOT FOUND THEN
                        INSERT INTO asset.call_number (owning_lib, record, create_date, edit_date, creator, editor, label)
                            VALUES (uri_owner_id, bib_id, 'now', 'now', editor_id, editor_id, '##URI##');
                        SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    END IF;

                    -- now, link them if they're not already
                    SELECT id INTO uri_map_id FROM asset.uri_call_number_map WHERE call_number = uri_cn_id AND uri = uri_id;
                    IF NOT FOUND THEN
                        INSERT INTO asset.uri_call_number_map (call_number, uri) VALUES (uri_cn_id, uri_id);
                    END IF;

                END LOOP;

            END IF;

        END LOOP;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.remap_metarecord_for_bib( bib_id BIGINT, fp TEXT, bib_is_deleted BOOL DEFAULT FALSE, retain_deleted BOOL DEFAULT FALSE ) RETURNS BIGINT AS $func$
DECLARE
    new_mapping     BOOL := TRUE;
    source_count    INT;
    old_mr          BIGINT;
    tmp_mr          metabib.metarecord%ROWTYPE;
    deleted_mrs     BIGINT[];
BEGIN

    -- We need to make sure we're not a deleted master record of an MR
    IF bib_is_deleted THEN
        FOR old_mr IN SELECT id FROM metabib.metarecord WHERE master_record = bib_id LOOP

            IF NOT retain_deleted THEN -- Go away for any MR that we're master of, unless retained
                DELETE FROM metabib.metarecord_source_map WHERE source = bib_id;
            END IF;

            -- Now, are there any more sources on this MR?
            SELECT COUNT(*) INTO source_count FROM metabib.metarecord_source_map WHERE metarecord = old_mr;

            IF source_count = 0 AND NOT retain_deleted THEN -- No other records
                deleted_mrs := ARRAY_APPEND(deleted_mrs, old_mr); -- Just in case...
                DELETE FROM metabib.metarecord WHERE id = old_mr;

            ELSE -- indeed there are. Update it with a null cache and recalcualated master record
                UPDATE  metabib.metarecord
                  SET   mods = NULL,
                        master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp AND NOT deleted ORDER BY quality DESC LIMIT 1)
                  WHERE id = old_mr;
            END IF;
        END LOOP;

    ELSE -- insert or update

        FOR tmp_mr IN SELECT m.* FROM metabib.metarecord m JOIN metabib.metarecord_source_map s ON (s.metarecord = m.id) WHERE s.source = bib_id LOOP

            -- Find the first fingerprint-matching
            IF old_mr IS NULL AND fp = tmp_mr.fingerprint THEN
                old_mr := tmp_mr.id;
                new_mapping := FALSE;

            ELSE -- Our fingerprint changed ... maybe remove the old MR
                DELETE FROM metabib.metarecord_source_map WHERE metarecord = tmp_mr.id AND source = bib_id; -- remove the old source mapping
                SELECT COUNT(*) INTO source_count FROM metabib.metarecord_source_map WHERE metarecord = tmp_mr.id;
                IF source_count = 0 THEN -- No other records
                    deleted_mrs := ARRAY_APPEND(deleted_mrs, tmp_mr.id);
                    DELETE FROM metabib.metarecord WHERE id = tmp_mr.id;
                END IF;
            END IF;

        END LOOP;

        -- we found no suitable, preexisting MR based on old source maps
        IF old_mr IS NULL THEN
            SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp; -- is there one for our current fingerprint?

            IF old_mr IS NULL THEN -- nope, create one and grab its id
                INSERT INTO metabib.metarecord ( fingerprint, master_record ) VALUES ( fp, bib_id );
                SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp;

            ELSE -- indeed there is. update it with a null cache and recalcualated master record
                UPDATE  metabib.metarecord
                  SET   mods = NULL,
                        master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp AND NOT deleted ORDER BY quality DESC LIMIT 1)
                  WHERE id = old_mr;
            END IF;

        ELSE -- there was one we already attached to, update its mods cache and master_record
            UPDATE  metabib.metarecord
              SET   mods = NULL,
                    master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp AND NOT deleted ORDER BY quality DESC LIMIT 1)
              WHERE id = old_mr;
        END IF;

        IF new_mapping THEN
            INSERT INTO metabib.metarecord_source_map (metarecord, source) VALUES (old_mr, bib_id); -- new source mapping
        END IF;

    END IF;

    IF ARRAY_UPPER(deleted_mrs,1) > 0 THEN
        UPDATE action.hold_request SET target = old_mr WHERE target IN ( SELECT unnest(deleted_mrs) ) AND hold_type = 'M'; -- if we had to delete any MRs above, make sure their holds are moved
    END IF;

    RETURN old_mr;

END;
$func$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION biblio.map_authority_linking (bibid BIGINT, marc TEXT) RETURNS BIGINT AS $func$
    DELETE FROM authority.bib_linking WHERE bib = $1;
    INSERT INTO authority.bib_linking (bib, authority)
        SELECT  y.bib,
                y.authority
          FROM (    SELECT  DISTINCT $1 AS bib,
                            BTRIM(remove_paren_substring(txt))::BIGINT AS authority
                      FROM  unnest(oils_xpath('//*[@code="0"]/text()',$2)) x(txt)
                      WHERE BTRIM(remove_paren_substring(txt)) ~ $re$^\d+$$re$
                ) y JOIN authority.record_entry r ON r.id = y.authority;
    SELECT $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.reingest_record_attributes (rid BIGINT, pattr_list TEXT[] DEFAULT NULL, prmarc TEXT DEFAULT NULL, rdeleted BOOL DEFAULT TRUE) RETURNS VOID AS $func$
DECLARE
    transformed_xml TEXT;
    rmarc           TEXT := prmarc;
    tmp_val         TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_vector     INT[] := '{}'::INT[];
    attr_vector_tmp INT[];
    attr_list       TEXT[] := pattr_list;
    attr_value      TEXT[];
    norm_attr_value TEXT[];
    tmp_xml         TEXT;
    attr_def        config.record_attr_definition%ROWTYPE;
    ccvm_row        config.coded_value_map%ROWTYPE;
BEGIN

    IF attr_list IS NULL OR rdeleted THEN -- need to do the full dance on INSERT or undelete
        SELECT ARRAY_AGG(name) INTO attr_list FROM config.record_attr_definition
        WHERE (
            tag IS NOT NULL OR
            fixed_field IS NOT NULL OR
            xpath IS NOT NULL OR
            phys_char_sf IS NOT NULL OR
            composite
        ) AND (
            filter OR sorter
        );
    END IF;

    IF rmarc IS NULL THEN
        SELECT marc INTO rmarc FROM biblio.record_entry WHERE id = rid;
    END IF;

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE NOT composite AND name = ANY( attr_list ) ORDER BY format LOOP

        attr_value := '{}'::TEXT[];
        norm_attr_value := '{}'::TEXT[];
        attr_vector_tmp := '{}'::INT[];

        SELECT * INTO ccvm_row FROM config.coded_value_map c WHERE c.ctype = attr_def.name LIMIT 1; 

        -- tag+sf attrs only support SVF
        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  ARRAY[ARRAY_TO_STRING(ARRAY_AGG(value), COALESCE(attr_def.joiner,' '))] INTO attr_value
              FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
              WHERE record = rid
                    AND tag LIKE attr_def.tag
                    AND CASE
                        WHEN attr_def.sf_list IS NOT NULL 
                            THEN POSITION(subfield IN attr_def.sf_list) > 0
                        ELSE TRUE
                    END
              GROUP BY tag
              ORDER BY tag
              LIMIT 1;

        ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
            attr_value := vandelay.marc21_extract_fixed_field_list(rmarc, attr_def.fixed_field);

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
        
            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(rmarc,xfrm.xslt);
                ELSE
                    transformed_xml := rmarc;
                END IF;
    
                prev_xfrm := xfrm.name;
            END IF;

            IF xfrm.name IS NULL THEN
                -- just grab the marcxml (empty) transform
                SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                prev_xfrm := xfrm.name;
            END IF;

            FOR tmp_xml IN SELECT UNNEST(oils_xpath(attr_def.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]])) LOOP
                tmp_val := oils_xpath_string(
                                '//*',
                                tmp_xml,
                                COALESCE(attr_def.joiner,' '),
                                ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                            );
                IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                    attr_value := attr_value || tmp_val;
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END LOOP;

        ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
            SELECT  ARRAY_AGG(m.value) INTO attr_value
              FROM  vandelay.marc21_physical_characteristics(rmarc) v
                    LEFT JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
              WHERE v.subfield = attr_def.phys_char_sf AND (m.value IS NOT NULL AND BTRIM(m.value) <> '')
                    AND ( ccvm_row.id IS NULL OR ( ccvm_row.id IS NOT NULL AND v.id IS NOT NULL) );

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        END IF;

                -- apply index normalizers to attr_value
        FOR tmp_val IN SELECT value FROM UNNEST(attr_value) x(value) LOOP
            FOR normalizer IN
                SELECT  n.func AS func,
                        n.param_count AS param_count,
                        m.params AS params
                  FROM  config.index_normalizer n
                        JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                  WHERE attr = attr_def.name
                  ORDER BY m.pos LOOP
                    EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    COALESCE( quote_literal( tmp_val ), 'NULL' ) ||
                        CASE
                            WHEN normalizer.param_count > 0
                                THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                ELSE ''
                            END ||
                    ')' INTO tmp_val;

            END LOOP;
            IF tmp_val IS NOT NULL AND tmp_val <> '' THEN
                -- note that a string that contains only blanks
                -- is a valid value for some attributes
                norm_attr_value := norm_attr_value || tmp_val;
            END IF;
        END LOOP;
        
        IF attr_def.filter THEN
            -- Create unknown uncontrolled values and find the IDs of the values
            IF ccvm_row.id IS NULL THEN
                FOR tmp_val IN SELECT value FROM UNNEST(norm_attr_value) x(value) LOOP
                    IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                        BEGIN -- use subtransaction to isolate unique constraint violations
                            INSERT INTO metabib.uncontrolled_record_attr_value ( attr, value ) VALUES ( attr_def.name, tmp_val );
                        EXCEPTION WHEN unique_violation THEN END;
                    END IF;
                END LOOP;

                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM metabib.uncontrolled_record_attr_value WHERE attr = attr_def.name AND value = ANY( norm_attr_value );
            ELSE
                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM config.coded_value_map WHERE ctype = attr_def.name AND code = ANY( norm_attr_value );
            END IF;

            -- Add the new value to the vector
            attr_vector := attr_vector || attr_vector_tmp;
        END IF;

        IF attr_def.sorter THEN
            DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
            IF norm_attr_value[1] IS NOT NULL THEN
                INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, norm_attr_value[1]);
            END IF;
        END IF;

    END LOOP;

/* We may need to rewrite the vlist to contain
   the intersection of new values for requested
   attrs and old values for ignored attrs. To
   do this, we take the old attr vlist and
   subtract any values that are valid for the
   requested attrs, and then add back the new
   set of attr values. */

    IF ARRAY_LENGTH(pattr_list, 1) > 0 THEN 
        SELECT vlist INTO attr_vector_tmp FROM metabib.record_attr_vector_list WHERE source = rid;
        SELECT attr_vector_tmp - ARRAY_AGG(id::INT) INTO attr_vector_tmp FROM metabib.full_attr_id_map WHERE attr = ANY (pattr_list);
        attr_vector := attr_vector || attr_vector_tmp;
    END IF;

    -- On to composite attributes, now that the record attrs have been pulled.  Processed in name order, so later composite
    -- attributes can depend on earlier ones.
    PERFORM metabib.compile_composite_attr_cache_init();
    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE composite AND name = ANY( attr_list ) ORDER BY name LOOP

        FOR ccvm_row IN SELECT * FROM config.coded_value_map c WHERE c.ctype = attr_def.name ORDER BY value LOOP

            tmp_val := metabib.compile_composite_attr( ccvm_row.id );
            CONTINUE WHEN tmp_val IS NULL OR tmp_val = ''; -- nothing to do

            IF attr_def.filter THEN
                IF attr_vector @@ tmp_val::query_int THEN
                    attr_vector = attr_vector + intset(ccvm_row.id);
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END IF;

            IF attr_def.sorter THEN
                IF attr_vector @@ tmp_val THEN
                    DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
                    INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, ccvm_row.code);
                END IF;
            END IF;

        END LOOP;

    END LOOP;

    IF ARRAY_LENGTH(attr_vector, 1) > 0 THEN
        IF rdeleted THEN -- initial insert OR revivication
            DELETE FROM metabib.record_attr_vector_list WHERE source = rid;
            INSERT INTO metabib.record_attr_vector_list (source, vlist) VALUES (rid, attr_vector);
        ELSE
            UPDATE metabib.record_attr_vector_list SET vlist = attr_vector WHERE source = rid;
        END IF;
    END IF;

END;

$func$ LANGUAGE PLPGSQL;


-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    tmp_bool BOOL;
BEGIN

    IF NEW.deleted THEN -- If this bib is deleted

        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;

        tmp_bool := FOUND; -- Just in case this is changed by some other statement

        PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint, TRUE, tmp_bool );

        IF NOT tmp_bool THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.record_attr_vector_list WHERE source = NEW.id;
        END IF;

        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.reingest_record_attributes(NEW.id, NULL, NEW.marc, TG_OP = 'INSERT' OR OLD.deleted);
        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.browse_normalize(facet_text TEXT, mapped_field INT) RETURNS TEXT AS $$
DECLARE
    normalizer  RECORD;
BEGIN

    FOR normalizer IN
        SELECT  n.func AS func,
                n.param_count AS param_count,
                m.params AS params
          FROM  config.index_normalizer n
                JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
          WHERE m.field = mapped_field AND m.pos < 0
          ORDER BY m.pos LOOP

            EXECUTE 'SELECT ' || normalizer.func || '(' ||
                quote_literal( facet_text ) ||
                CASE
                    WHEN normalizer.param_count > 0
                        THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                        ELSE ''
                    END ||
                ')' INTO facet_text;

    END LOOP;

    RETURN facet_text;
END;

$$ LANGUAGE PLPGSQL;


-- This mimics a specific part of QueryParser, turning the first part of a
-- classed search (search_class) into a set of classes and possibly fields.
-- search_class might look like "author" or "title|proper" or "ti|uniform"
-- or "au" or "au|corporate|personal" or anything like that, where the first
-- element of the list you get by separating on the "|" character is either
-- a registered class (config.metabib_class) or an alias
-- (config.metabib_search_alias), and the rest of any such elements are
-- fields (config.metabib_field).
CREATE OR REPLACE
    FUNCTION metabib.search_class_to_registered_components(search_class TEXT)
    RETURNS SETOF RECORD AS $func$
DECLARE
    search_parts        TEXT[];
    field_name          TEXT;
    search_part_count   INTEGER;
    rec                 RECORD;
    registered_class    config.metabib_class%ROWTYPE;
    registered_alias    config.metabib_search_alias%ROWTYPE;
    registered_field    config.metabib_field%ROWTYPE;
BEGIN
    search_parts := REGEXP_SPLIT_TO_ARRAY(search_class, E'\\|');

    search_part_count := ARRAY_LENGTH(search_parts, 1);
    IF search_part_count = 0 THEN
        RETURN;
    ELSE
        SELECT INTO registered_class
            * FROM config.metabib_class WHERE name = search_parts[1];
        IF FOUND THEN
            IF search_part_count < 2 THEN   -- all fields
                rec := (registered_class.name, NULL::INTEGER);
                RETURN NEXT rec;
                RETURN; -- done
            END IF;
            FOR field_name IN SELECT *
                FROM UNNEST(search_parts[2:search_part_count]) LOOP
                SELECT INTO registered_field
                    * FROM config.metabib_field
                    WHERE name = field_name AND
                        field_class = registered_class.name;
                IF FOUND THEN
                    rec := (registered_class.name, registered_field.id);
                    RETURN NEXT rec;
                END IF;
            END LOOP;
        ELSE
            -- maybe we have an alias?
            SELECT INTO registered_alias
                * FROM config.metabib_search_alias WHERE alias=search_parts[1];
            IF NOT FOUND THEN
                RETURN;
            ELSE
                IF search_part_count < 2 THEN   -- return w/e the alias says
                    rec := (
                        registered_alias.field_class, registered_alias.field
                    );
                    RETURN NEXT rec;
                    RETURN; -- done
                ELSE
                    FOR field_name IN SELECT *
                        FROM UNNEST(search_parts[2:search_part_count]) LOOP
                        SELECT INTO registered_field
                            * FROM config.metabib_field
                            WHERE name = field_name AND
                                field_class = registered_alias.field_class;
                        IF FOUND THEN
                            rec := (
                                registered_alias.field_class,
                                registered_field.id
                            );
                            RETURN NEXT rec;
                        END IF;
                    END LOOP;
                END IF;
            END IF;
        END IF;
    END IF;
END;
$func$ LANGUAGE PLPGSQL ROWS 1;


-- Given a string such as a user might type into a search box, prepare
-- two changed variants for TO_TSQUERY(). See
-- http://www.postgresql.org/docs/9.0/static/textsearch-controls.html
-- The first variant is normalized to match indexed documents regardless
-- of diacritics.  The second variant keeps its diacritics for proper
-- highlighting via TS_HEADLINE().
CREATE OR REPLACE
    FUNCTION metabib.autosuggest_prepare_tsquery(orig TEXT) RETURNS TEXT[] AS
$$
DECLARE
    orig_ended_in_space     BOOLEAN;
    result                  RECORD;
    plain                   TEXT;
    normalized              TEXT;
BEGIN
    orig_ended_in_space := orig ~ E'\\s$';

    orig := ARRAY_TO_STRING(
        evergreen.regexp_split_to_array(orig, E'\\W+'), ' '
    );

    normalized := public.naco_normalize(orig); -- also trim()s
    plain := trim(orig);

    IF NOT orig_ended_in_space THEN
        plain := plain || ':*';
        normalized := normalized || ':*';
    END IF;

    plain := ARRAY_TO_STRING(
        evergreen.regexp_split_to_array(plain, E'\\s+'), ' & '
    );
    normalized := ARRAY_TO_STRING(
        evergreen.regexp_split_to_array(normalized, E'\\s+'), ' & '
    );

    RETURN ARRAY[normalized, plain];
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE
    FUNCTION metabib.suggest_browse_entries(
        raw_query_text  TEXT,   -- actually typed by humans at the UI level
        search_class    TEXT,   -- 'alias' or 'class' or 'class|field..', etc
        headline_opts   TEXT,   -- markup options for ts_headline()
        visibility_org  INTEGER,-- null if you don't want opac visibility test
        query_limit     INTEGER,-- use in LIMIT clause of interal query
        normalization   INTEGER -- argument to TS_RANK_CD()
    ) RETURNS TABLE (
        value                   TEXT,   -- plain
        field                   INTEGER,
        buoyant_and_class_match BOOL,
        field_match             BOOL,
        field_weight            INTEGER,
        rank                    REAL,
        buoyant                 BOOL,
        match                   TEXT    -- marked up
    ) AS $func$
DECLARE
    prepared_query_texts    TEXT[];
    query                   TSQUERY;
    plain_query             TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
BEGIN
    prepared_query_texts := metabib.autosuggest_prepare_tsquery(raw_query_text);

    query := TO_TSQUERY('keyword', prepared_query_texts[1]);
    plain_query := TO_TSQUERY('keyword', prepared_query_texts[2]);

    visibility_org := NULLIF(visibility_org,-1);
    IF visibility_org IS NOT NULL THEN
        opac_visibility_join := '
    JOIN asset.opac_visible_copies aovc ON (
        aovc.record = x.source AND
        aovc.circ_lib IN (SELECT id FROM actor.org_unit_descendants($4))
    )';
    ELSE
        opac_visibility_join := '';
    END IF;

    -- The following determines whether we only provide suggestsons matching
    -- the user's selected search_class, or whether we show other suggestions
    -- too. The reason for MIN() is that for search_classes like
    -- 'title|proper|uniform' you would otherwise get multiple rows.  The
    -- implication is that if title as a class doesn't have restrict,
    -- nor does the proper field, but the uniform field does, you're going
    -- to get 'false' for your overall evaluation of 'should we restrict?'
    -- To invert that, change from MIN() to MAX().

    SELECT
        INTO r_fields
            MIN(cmc.restrict::INT) AS restrict_class,
            MIN(cmf.restrict::INT) AS restrict_field
        FROM metabib.search_class_to_registered_components(search_class)
            AS _registered (field_class TEXT, field INT)
        JOIN
            config.metabib_class cmc ON (cmc.name = _registered.field_class)
        LEFT JOIN
            config.metabib_field cmf ON (cmf.id = _registered.field);

    -- evaluate 'should we restrict?'
    IF r_fields.restrict_field::BOOL OR r_fields.restrict_class::BOOL THEN
        search_class_join := '
    JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            (_registered.field IS NULL AND
                _registered.field_class = cmf.field_class) OR
            (_registered.field = cmf.id)
        )
    ';
    ELSE
        search_class_join := '
    LEFT JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            _registered.field_class = cmc.name
        )
    ';
    END IF;

    RETURN QUERY EXECUTE '
SELECT  DISTINCT
        x.value,
        x.id,
        x.push,
        x.restrict,
        x.weight,
        x.ts_rank_cd,
        x.buoyant,
        TS_HEADLINE(value, $7, $3)
  FROM  (SELECT DISTINCT
                mbe.value,
                cmf.id,
                cmc.buoyant AND _registered.field_class IS NOT NULL AS push,
                _registered.field = cmf.id AS restrict,
                cmf.weight,
                TS_RANK_CD(mbe.index_vector, $1, $6),
                cmc.buoyant,
                mbedm.source
          FROM  metabib.browse_entry_def_map mbedm
                JOIN (SELECT * FROM metabib.browse_entry WHERE index_vector @@ $1 LIMIT 10000) mbe ON (mbe.id = mbedm.entry)
                JOIN config.metabib_field cmf ON (cmf.id = mbedm.def)
                JOIN config.metabib_class cmc ON (cmf.field_class = cmc.name)
                '  || search_class_join || '
          ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
          LIMIT 1000) AS x
        ' || opac_visibility_join || '
  ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
  LIMIT $5
'   -- sic, repeat the order by clause in the outer select too
    USING
        query, search_class, headline_opts,
        visibility_org, query_limit, normalization, plain_query
        ;

    -- sort order:
    --  buoyant AND chosen class = match class
    --  chosen field = match field
    --  field weight
    --  rank
    --  buoyancy
    --  value itself

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION public.oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
    normalizer      RECORD;
    value           TEXT := '';
    temp_vector     TEXT := '';
    ts_rec          RECORD;
    cur_weight      "char";
BEGIN

    value := NEW.value;
    NEW.index_vector = ''::tsvector;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos < 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;

        NEW.value = value;

        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos >= 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;
   END IF;

    IF TG_TABLE_NAME::TEXT ~ 'browse_entry$' THEN

        value :=  ARRAY_TO_STRING(
            evergreen.regexp_split_to_array(value, E'\\W+'), ' '
        );
        value := public.search_normalize(value);
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);

    ELSIF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR ts_rec IN

            SELECT DISTINCT m.ts_config, m.index_weight
            FROM config.metabib_class_ts_map m
                 LEFT JOIN metabib.record_attr_vector_list r ON (r.source = NEW.source)
                 LEFT JOIN config.coded_value_map ccvm ON (
                    ccvm.ctype IN ('item_lang', 'language') AND
                    ccvm.code = m.index_lang AND
                    r.vlist @> intset(ccvm.id)
                )
            WHERE m.field_class = TG_ARGV[0]
                AND m.active
                AND (m.always OR NOT EXISTS (SELECT 1 FROM config.metabib_field_ts_map WHERE metabib_field = NEW.field))
                AND (m.index_lang IS NULL OR ccvm.id IS NOT NULL)
                        UNION
            SELECT DISTINCT m.ts_config, m.index_weight
            FROM config.metabib_field_ts_map m
                 LEFT JOIN metabib.record_attr_vector_list r ON (r.source = NEW.source)
                 LEFT JOIN config.coded_value_map ccvm ON (
                    ccvm.ctype IN ('item_lang', 'language') AND
                    ccvm.code = m.index_lang AND
                    r.vlist @> intset(ccvm.id)
                )
            WHERE m.metabib_field = NEW.field
                AND m.active
                AND (m.index_lang IS NULL OR ccvm.id IS NOT NULL)
            ORDER BY index_weight ASC

        LOOP

            IF cur_weight IS NOT NULL AND cur_weight != ts_rec.index_weight THEN
                NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
                temp_vector = '';
            END IF;

            cur_weight = ts_rec.index_weight;
            SELECT INTO temp_vector temp_vector || ' ' || to_tsvector(ts_rec.ts_config::regconfig, value)::TEXT;

        END LOOP;
        NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
    ELSE
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;


CREATE TYPE metabib.flat_browse_entry_appearance AS (
    browse_entry    BIGINT,
    value           TEXT,
    fields          TEXT,
    authorities     TEXT,
    sees            TEXT,
    sources         INT,        -- visible ones, that is
    asources        INT,        -- visible ones, that is
    row_number      INT,        -- internal use, sort of
    accurate        BOOL,       -- Count in sources field is accurate? Not
                                -- if we had more than a browse superpage
                                -- of records to look at.
    aaccurate       BOOL,       -- See previous comment...
    pivot_point     BIGINT
);


CREATE OR REPLACE FUNCTION metabib.browse_bib_pivot(
    INT[],
    TEXT
) RETURNS BIGINT AS $p$
    SELECT  mbe.id
      FROM  metabib.browse_entry mbe
            JOIN metabib.browse_entry_def_map mbedm ON (
                mbedm.entry = mbe.id
                AND mbedm.def = ANY($1)
            )
      WHERE mbe.sort_value >= public.naco_normalize($2)
      ORDER BY mbe.sort_value, mbe.value LIMIT 1;
$p$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION metabib.browse_authority_pivot(
    INT[],
    TEXT
) RETURNS BIGINT AS $p$
    SELECT  mbe.id
      FROM  metabib.browse_entry mbe
            JOIN metabib.browse_entry_simple_heading_map mbeshm ON ( mbeshm.entry = mbe.id )
            JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
            JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                ash.atag = map.authority_field
                AND map.metabib_field = ANY($1)
            )
      WHERE mbe.sort_value >= public.naco_normalize($2)
      ORDER BY mbe.sort_value, mbe.value LIMIT 1;
$p$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION metabib.browse_authority_refs_pivot(
    INT[],
    TEXT
) RETURNS BIGINT AS $p$
    SELECT  mbe.id
      FROM  metabib.browse_entry mbe
            JOIN metabib.browse_entry_simple_heading_map mbeshm ON ( mbeshm.entry = mbe.id )
            JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
            JOIN authority.control_set_auth_field_metabib_field_map_refs_only map ON (
                ash.atag = map.authority_field
                AND map.metabib_field = ANY($1)
            )
      WHERE mbe.sort_value >= public.naco_normalize($2)
      ORDER BY mbe.sort_value, mbe.value LIMIT 1;
$p$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION metabib.browse_pivot(
    INT[],
    TEXT
) RETURNS BIGINT AS $p$
    SELECT  id FROM metabib.browse_entry
      WHERE id IN (
                metabib.browse_bib_pivot($1, $2),
                metabib.browse_authority_refs_pivot($1,$2) -- only look in 4xx, 5xx, 7xx of authority
            )
      ORDER BY sort_value, value LIMIT 1;
$p$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION metabib.staged_browse(
    query                   TEXT,
    fields                  INT[],
    context_org             INT,
    context_locations       INT[],
    staff                   BOOL,
    browse_superpage_size   INT,
    count_up_from_zero      BOOL,   -- if false, count down from -1
    result_limit            INT,
    next_pivot_pos          INT
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
DECLARE
    curs                    REFCURSOR;
    rec                     RECORD;
    qpfts_query             TEXT;
    aqpfts_query            TEXT;
    afields                 INT[];
    bfields                 INT[];
    result_row              metabib.flat_browse_entry_appearance%ROWTYPE;
    results_skipped         INT := 0;
    row_counter             INT := 0;
    row_number              INT;
    slice_start             INT;
    slice_end               INT;
    full_end                INT;
    all_records             BIGINT[];
    all_brecords             BIGINT[];
    all_arecords            BIGINT[];
    superpage_of_records    BIGINT[];
    superpage_size          INT;
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    OPEN curs FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;


        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
        SELECT INTO all_arecords, result_row.sees, afields
                ARRAY_AGG(DISTINCT abl.bib), -- bibs to check for visibility
                STRING_AGG(DISTINCT aal.source::TEXT, $$,$$), -- authority record ids
                ARRAY_AGG(DISTINCT map.metabib_field) -- authority-tag-linked CMF rows

          FROM  metabib.browse_entry_simple_heading_map mbeshm
                JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                JOIN authority.authority_linking aal ON ( ash.record = aal.source )
                JOIN authority.bib_linking abl ON ( aal.target = abl.authority )
                JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                    ash.atag = map.authority_field
                    AND map.metabib_field = ANY(fields)
                )
          WHERE mbeshm.entry = rec.id;


        -- Gather aggregate data based on the MBE row we're looking at now, bib axis
        SELECT INTO all_brecords, result_row.authorities, bfields
                ARRAY_AGG(DISTINCT source),
                STRING_AGG(DISTINCT authority::TEXT, $$,$$),
                ARRAY_AGG(DISTINCT def)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        SELECT INTO result_row.fields STRING_AGG(DISTINCT x::TEXT, $$,$$) FROM UNNEST(afields || bfields) x;

        result_row.sources := 0;
        result_row.asources := 0;

        -- Bib-linked vis checking
        IF ARRAY_UPPER(all_brecords,1) IS NOT NULL THEN

            full_end := ARRAY_LENGTH(all_brecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.sources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_brecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    'NULL AS badges, NULL::NUMERIC AS popularity, ' ||
                    '1::NUMERIC AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, until we've
                -- either exhausted that set of records or found at least 1
                -- visible record.

                SELECT INTO result_row.sources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;

            -- Accurate?  Well, probably.
            result_row.accurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            full_end := ARRAY_LENGTH(all_arecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.asources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_arecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    'NULL AS badges, NULL::NUMERIC AS popularity, ' ||
                    '1::NUMERIC AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, via
                -- authority until we've either exhausted that set of records
                -- or found at least 1 visible record.

                SELECT INTO result_row.asources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;


            -- Accurate?  Well, probably.
            result_row.aaccurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

        END IF;

        IF result_row.sources > 0 OR result_row.asources > 0 THEN

            -- The function that calls this function needs row_number in order
            -- to correctly order results from two different runs of this
            -- functions.
            result_row.row_number := row_number;

            -- Now, if row_counter is still less than limit, return a row.  If
            -- not, but it is less than next_pivot_pos, continue on without
            -- returning actual result rows until we find
            -- that next pivot, and return it.

            IF row_counter < result_limit THEN
                result_row.browse_entry := rec.id;
                result_row.value := rec.value;

                RETURN NEXT result_row;
            ELSE
                result_row.browse_entry := NULL;
                result_row.authorities := NULL;
                result_row.fields := NULL;
                result_row.value := NULL;
                result_row.sources := NULL;
                result_row.sees := NULL;
                result_row.accurate := NULL;
                result_row.aaccurate := NULL;
                result_row.pivot_point := rec.id;

                IF row_counter >= next_pivot_pos THEN
                    RETURN NEXT result_row;
                    RETURN;
                END IF;
            END IF;

            IF count_up_from_zero THEN
                row_number := row_number + 1;
            ELSE
                row_number := row_number - 1;
            END IF;

            -- row_counter is different from row_number.
            -- It simply counts up from zero so that we know when
            -- we've reached our limit.
            row_counter := row_counter + 1;
        END IF;
    END LOOP;
END;
$p$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION metabib.browse(
    search_field            INT[],
    browse_term             TEXT,
    context_org             INT DEFAULT NULL,
    context_loc_group       INT DEFAULT NULL,
    staff                   BOOL DEFAULT FALSE,
    pivot_id                BIGINT DEFAULT NULL,
    result_limit            INT DEFAULT 10
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
DECLARE
    core_query              TEXT;
    back_query              TEXT;
    forward_query           TEXT;
    pivot_sort_value        TEXT;
    pivot_sort_fallback     TEXT;
    context_locations       INT[];
    browse_superpage_size   INT;
    results_skipped         INT := 0;
    back_limit              INT;
    back_to_pivot           INT;
    forward_limit           INT;
    forward_to_pivot        INT;
BEGIN
    -- First, find the pivot if we were given a browse term but not a pivot.
    IF pivot_id IS NULL THEN
        pivot_id := metabib.browse_pivot(search_field, browse_term);
    END IF;

    SELECT INTO pivot_sort_value, pivot_sort_fallback
        sort_value, value FROM metabib.browse_entry WHERE id = pivot_id;

    -- Bail if we couldn't find a pivot.
    IF pivot_sort_value IS NULL THEN
        RETURN;
    END IF;

    -- Transform the context_loc_group argument (if any) (logc at the
    -- TPAC layer) into a form we'll be able to use.
    IF context_loc_group IS NOT NULL THEN
        SELECT INTO context_locations ARRAY_AGG(location)
            FROM asset.copy_location_group_map
            WHERE lgroup = context_loc_group;
    END IF;

    -- Get the configured size of browse superpages.
    SELECT INTO browse_superpage_size value     -- NULL ok
        FROM config.global_flag
        WHERE enabled AND name = 'opac.browse.holdings_visibility_test_limit';

    -- First we're going to search backward from the pivot, then we're going
    -- to search forward.  In each direction, we need two limits.  At the
    -- lesser of the two limits, we delineate the edge of the result set
    -- we're going to return.  At the greater of the two limits, we find the
    -- pivot value that would represent an offset from the current pivot
    -- at a distance of one "page" in either direction, where a "page" is a
    -- result set of the size specified in the "result_limit" argument.
    --
    -- The two limits in each direction make four derived values in total,
    -- and we calculate them now.
    back_limit := CEIL(result_limit::FLOAT / 2);
    back_to_pivot := result_limit;
    forward_limit := result_limit / 2;
    forward_to_pivot := result_limit - 1;

    -- This is the meat of the SQL query that finds browse entries.  We'll
    -- pass this to a function which uses it with a cursor, so that individual
    -- rows may be fetched in a loop until some condition is satisfied, without
    -- waiting for a result set of fixed size to be collected all at once.
    core_query := '
SELECT  mbe.id,
        mbe.value,
        mbe.sort_value
  FROM  metabib.browse_entry mbe
  WHERE (
            EXISTS ( -- are there any bibs using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_def_map mbedm
                  WHERE mbedm.entry = mbe.id AND mbedm.def = ANY(' || quote_literal(search_field) || ')
                  LIMIT 1
            ) OR EXISTS ( -- are there any authorities using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_simple_heading_map mbeshm
                        JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                        JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                            ash.atag = map.authority_field
                            AND map.metabib_field = ANY(' || quote_literal(search_field) || ')
                        )
                  WHERE mbeshm.entry = mbe.id
            )
        ) AND ';

    -- This is the variant of the query for browsing backward.
    back_query := core_query ||
        ' mbe.sort_value <= ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value DESC, mbe.value DESC ';

    -- This variant browses forward.
    forward_query := core_query ||
        ' mbe.sort_value > ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value, mbe.value ';

    -- We now call the function which applies a cursor to the provided
    -- queries, stopping at the appropriate limits and also giving us
    -- the next page's pivot.
    RETURN QUERY
        SELECT * FROM metabib.staged_browse(
            back_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, TRUE, back_limit, back_to_pivot
        ) UNION
        SELECT * FROM metabib.staged_browse(
            forward_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, FALSE, forward_limit, forward_to_pivot
        ) ORDER BY row_number DESC;

END;
$p$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.browse(
    search_class        TEXT,
    browse_term         TEXT,
    context_org         INT DEFAULT NULL,
    context_loc_group   INT DEFAULT NULL,
    staff               BOOL DEFAULT FALSE,
    pivot_id            BIGINT DEFAULT NULL,
    result_limit        INT DEFAULT 10
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
BEGIN
    RETURN QUERY SELECT * FROM metabib.browse(
        (SELECT COALESCE(ARRAY_AGG(id), ARRAY[]::INT[])
            FROM config.metabib_field WHERE field_class = search_class),
        browse_term,
        context_org,
        context_loc_group,
        staff,
        pivot_id,
        result_limit
    );
END;
$p$ LANGUAGE PLPGSQL;

-- This function is used to help clean up facet labels. Due to quirks in
-- MARC parsing, some facet labels may be generated with periods or commas
-- at the end.  This will strip a trailing commas off all the time, and
-- periods when they don't look like they are part of initials.
--      Smith, John    =>  no change
--      Smith, John,   =>  Smith, John
--      Smith, John.   =>  Smith, John
--      Public, John Q. => no change
CREATE OR REPLACE FUNCTION metabib.trim_trailing_punctuation ( TEXT ) RETURNS TEXT AS $$
DECLARE
    result    TEXT;
    last_char TEXT;
BEGIN
    result := $1;
    last_char = substring(result from '.$');

    IF last_char = ',' THEN
        result := substring(result from '^(.*),$');

    ELSIF last_char = '.' THEN
        IF substring(result from ' \w\.$') IS NULL THEN
            result := substring(result from '^(.*)\.$');
        END IF;
    END IF;

    RETURN result;

END;
$$ language 'plpgsql';

COMMIT;

