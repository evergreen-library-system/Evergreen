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

DROP SCHEMA metabib CASCADE;

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
CREATE INDEX metabib_subject_field_entry_source_idx ON metabib.subject_field_entry (source);


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


CREATE TABLE metabib.rec_descriptor (
	id		BIGSERIAL PRIMARY KEY,
	record		BIGINT,
	item_type	TEXT,
	item_form	TEXT,
	bib_level	TEXT,
	control_type	TEXT,
	char_encoding	TEXT,
	enc_level	TEXT,
	audience	TEXT,
	lit_form	TEXT,
	type_mat	TEXT,
	cat_form	TEXT,
	pub_status	TEXT,
	item_lang	TEXT,
	vr_format	TEXT,
	date1		TEXT,
	date2		TEXT
);
CREATE INDEX metabib_rec_descriptor_record_idx ON metabib.rec_descriptor (record);
/* We may not need these...

CREATE INDEX metabib_rec_descriptor_item_type_idx ON metabib.rec_descriptor (item_type);
CREATE INDEX metabib_rec_descriptor_item_form_idx ON metabib.rec_descriptor (item_form);
CREATE INDEX metabib_rec_descriptor_bib_level_idx ON metabib.rec_descriptor (bib_level);
CREATE INDEX metabib_rec_descriptor_control_type_idx ON metabib.rec_descriptor (control_type);
CREATE INDEX metabib_rec_descriptor_char_encoding_idx ON metabib.rec_descriptor (char_encoding);
CREATE INDEX metabib_rec_descriptor_enc_level_idx ON metabib.rec_descriptor (enc_level);
CREATE INDEX metabib_rec_descriptor_audience_idx ON metabib.rec_descriptor (audience);
CREATE INDEX metabib_rec_descriptor_lit_form_idx ON metabib.rec_descriptor (lit_form);
CREATE INDEX metabib_rec_descriptor_cat_form_idx ON metabib.rec_descriptor (cat_form);
CREATE INDEX metabib_rec_descriptor_pub_status_idx ON metabib.rec_descriptor (pub_status);
CREATE INDEX metabib_rec_descriptor_item_lang_idx ON metabib.rec_descriptor (item_lang);
CREATE INDEX metabib_rec_descriptor_vr_format_idx ON metabib.rec_descriptor (vr_format);

*/

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

CREATE FUNCTION version_specific_xpath () RETURNS TEXT AS $wrapper_function$
DECLARE
	out_text TEXT;
BEGIN

	IF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT < 8.3 THEN
		out_text := 'Creating XPath functions that work like the native XPATH function in 8.3+';

		EXECUTE $create_82_funcs$

CREATE OR REPLACE FUNCTION oils_xpath ( xpath TEXT, xml TEXT, ns ANYARRAY ) RETURNS TEXT[] AS $func$
DECLARE
	node_text	TEXT;
	ns_regexp	TEXT;
	munged_xpath	TEXT;
BEGIN
	
	munged_xpath := xpath;

	IF ns IS NOT NULL THEN
		FOR namespace IN 1 .. array_upper(ns, 1) LOOP
			munged_xpath := REGEXP_REPLACE(
				munged_xpath,
				E'(' || ns[namespace][1] || E'):(\\w+)',
				E'*[local-name() = "\\2" and namespace-uri() = "' || ns[namespace][2] || E'"]',
				'g'
			);
		END LOOP;

		munged_xpath := REGEXP_REPLACE( munged_xpath, E'\\]\\[(\\D)',E' and \\1', 'g');
	END IF;

	node_text := xpath_nodeset(xml, munged_xpath, 'XXX_OILS_NODESET');
	node_text := REGEXP_REPLACE(node_text,'^<XXX_OILS_NODESET>', '');
	node_text := REGEXP_REPLACE(node_text,'</XXX_OILS_NODESET>$', '');

	RETURN  STRING_TO_ARRAY(node_text, '</XXX_OILS_NODESET><XXX_OILS_NODESET>');
END;
$func$ LANGUAGE PLPGSQL; 

CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT oils_xpath( $1, $2, NULL::TEXT[] );' LANGUAGE SQL; 

		$create_82_funcs$;
	ELSE
		out_text := 'Creating XPath wrapper functions around the native XPATH function in 8.3+';

		EXECUTE $create_83_funcs$
-- 8.3 or after
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML, $3 )::TEXT[];' LANGUAGE SQL; 
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML )::TEXT[];' LANGUAGE SQL; 

		$create_83_funcs$;

	END IF;

	RETURN out_text;
END;
$wrapper_function$ LANGUAGE PLPGSQL;

SELECT version_specific_xpath();
DROP FUNCTION version_specific_xpath();

CREATE TYPE metabib.field_entry_template AS (
        field_class     TEXT,
        field           INT,
        source          BIGINT,
        value           TEXT
);

CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( rid INT, default_joiner TEXT ) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
	bib		biblio.record_entry%ROWTYPE;
	idx		config.metabib_field%ROWTYPE;
	xfrm		config.xml_transform%ROWTYPE;
	prev_xfrm	TEXT;
	transformed_xml	TEXT;
	xml_node	TEXT;
	xml_node_list	TEXT[];
	raw_text	TEXT;
	joiner		TEXT := default_joiner; -- XXX will index defs supply a joiner?
	output_row	metabib.field_entry_template%ROWTYPE;
BEGIN

	-- Get the record
	SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

	-- Loop over the indexing entries
	FOR idx IN SELECT * FROM config.metabib_field ORDER BY format LOOP

		SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

		-- See if we can skip the XSLT ... it's expensive
		IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
			-- Can't skip the transform
			IF xfrm.xslt <> '---' THEN
				transformed_xml := xslt_process(bib.marc,xfrm.xslt);
			ELSE
				transformed_xml := bib.marc;
			END IF;

			prev_xfrm := xfrm.name;
		END IF;

		xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

		raw_text := NULL;
		FOR xml_node IN SELECT x FROM explode_array(xml_node_list) AS x LOOP
			IF raw_text IS NOT NULL THEN
				raw_text := raw_text || joiner;
			END IF;
			raw_text := COALESCE(raw_text,'') || ARRAY_TO_STRING(oils_xpath( '//text()', xml_node ), ' ');
		END LOOP;

		CONTINUE WHEN raw_text IS NULL;

		output_row.field_class = idx.field_class;
		output_row.field = idx.id;
		output_row.source = rid;
		output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'gs'));

		RETURN NEXT output_row;

	END LOOP;

END;
$func$ LANGUAGE PLPGSQL;

-- default to a space joiner
CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( INT ) RETURNS SETOF metabib.field_entry_template AS $func$
	SELECT * FROM biblio.extract_metabib_field_entry($1, ' ');
$func$ LANGUAGE SQL;

COMMIT;

