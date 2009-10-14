BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0035'); -- miker

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

