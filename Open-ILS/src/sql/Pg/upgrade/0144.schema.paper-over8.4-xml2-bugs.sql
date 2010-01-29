
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0144'); -- miker

CREATE FUNCTION version_specific_xpath () RETURNS TEXT AS $wrapper_function$
DECLARE
    out_text TEXT;
BEGIN

    IF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT < 8.3 THEN
        out_text := 'Creating XPath functions that work like the native XPATH function in 8.3+.  contrib/xml2 is required!';

        EXECUTE $create_82_funcs$

CREATE OR REPLACE FUNCTION oils_xpath ( xpath TEXT, xml TEXT, ns ANYARRAY ) RETURNS TEXT[] AS $func$
DECLARE
    node_text   TEXT;
    ns_regexp   TEXT;
    munged_xpath    TEXT;
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

    -- RAISE NOTICE 'munged xpath: %', munged_xpath;

    node_text := xpath_nodeset(xml, munged_xpath, 'XXX_OILS_NODESET');
    -- RAISE NOTICE 'node_text: %', node_text;

    IF munged_xpath ~ $re$/[^/[]*@[^/]+$$re$ THEN
        node_text := REGEXP_REPLACE(node_text,'<XXX_OILS_NODESET>[^"]+"', '<XXX_OILS_NODESET>', 'g');
        node_text := REGEXP_REPLACE(node_text,'"</XXX_OILS_NODESET>', '</XXX_OILS_NODESET>', 'g');
    END IF;

    node_text := REGEXP_REPLACE(node_text,'^<XXX_OILS_NODESET>', '');
    node_text := REGEXP_REPLACE(node_text,'</XXX_OILS_NODESET>$', '');

    RETURN  STRING_TO_ARRAY(node_text, '</XXX_OILS_NODESET><XXX_OILS_NODESET>');
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT oils_xpath( $1, $2, NULL::TEXT[] );' LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $$
    SELECT xslt_process( $1, $2 );
$$ LANGUAGE SQL;

        $create_82_funcs$;
    ELSIF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT = 8.3 THEN
        out_text := 'Creating XPath wrapper functions around the native XPATH function in 8.3.  contrib/xml2 still required!';

        EXECUTE $create_83_funcs$
-- 8.3 or after
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML, $3 )::TEXT[];' LANGUAGE SQL;
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML )::TEXT[];' LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $$
    SELECT xslt_process( $1, $2 );
$$ LANGUAGE SQL;

        $create_83_funcs$;

    ELSE
        out_text := 'Creating XPath wrapper functions around the native XPATH function in 8.4+, and plperlu-based xslt processor.  No contrib/xml2 needed!';

        EXECUTE $create_84_funcs$
-- 8.4 or after
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML, $3 )::TEXT[];' LANGUAGE SQL;
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML )::TEXT[];' LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $func$
  use strict;

  use XML::LibXSLT;
  use XML::LibXML;

  my $doc = shift;
  my $xslt = shift;

  # The following approach uses the older XML::LibXML 1.69 / XML::LibXSLT 1.68
  # methods of parsing XML documents and stylesheets, in the hopes of broader
  # compatibility with distributions
  my $parser = $_SHARED{'_xslt_process'}{parsers}{xml} || XML::LibXML->new();

  # Cache the XML parser, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xml} = $parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xml});

  my $xslt_parser = $_SHARED{'_xslt_process'}{parsers}{xslt} || XML::LibXSLT->new();

  # Cache the XSLT processor, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xslt} = $xslt_parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xslt});

  my $stylesheet = $_SHARED{'_xslt_process'}{stylesheets}{$xslt} ||
    $xslt_parser->parse_stylesheet( $parser->parse_string($xslt) );

  $_SHARED{'_xslt_process'}{stylesheets}{$xslt} = $stylesheet
    unless ($_SHARED{'_xslt_process'}{stylesheets}{$xslt});

  return $stylesheet->output_string(
    $stylesheet->transform(
      $parser->parse_string($doc)
    )
  );

$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

        $create_84_funcs$;
    END IF;

    RETURN out_text;
END;
$wrapper_function$ LANGUAGE PLPGSQL;

SELECT version_specific_xpath();
DROP FUNCTION version_specific_xpath();

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, TEXT, ANYARRAY ) RETURNS TEXT AS $func$
    SELECT  ARRAY_TO_STRING(
                oils_xpath(
                    $1 ||
                        CASE WHEN $1 ~ $re$/[^/[]*@[^/]+$$re$ OR $1 ~ $re$text\(\)$$re$ THEN '' ELSE '//text()' END,
                    $2,
                    $4
                ),
                $3
            );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, TEXT ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, $3, NULL::TEXT[] );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, '', $3 );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, NULL::TEXT[] );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xpath_table ( key TEXT, document_field TEXT, relation_name TEXT, xpaths TEXT, criteria TEXT ) RETURNS SETOF RECORD AS $func$
DECLARE
    xpath_list  TEXT[];
    select_list TEXT[];
    where_list  TEXT[];
    q           TEXT;
    out_record  RECORD;
    empty_test  RECORD;
BEGIN
    xpath_list := STRING_TO_ARRAY( xpaths, '|' );

    select_list := ARRAY_APPEND( select_list, key || '::INT AS key' );

    FOR i IN 1 .. ARRAY_UPPER(xpath_list,1) LOOP
        select_list := ARRAY_APPEND(
            select_list,
            $sel$
            EXPLODE_ARRAY(
                COALESCE(
                    NULLIF(
                        oils_xpath(
                            $sel$ ||
                                quote_literal(
                                    CASE
                                        WHEN xpath_list[i] ~ $re$/[^/[]*@[^/]+$$re$ OR xpath_list[i] ~ $re$text\(\)$$re$ THEN xpath_list[i]
                                        ELSE xpath_list[i] || '//text()'
                                    END
                                ) ||
                            $sel$,
                            $sel$ || document_field || $sel$
                        ),
                       '{}'::TEXT[]
                    ),
                    '{NULL}'::TEXT[]
                )
            ) AS c_$sel$ || i
        );
        where_list := ARRAY_APPEND(
            where_list,
            'c_' || i || ' IS NOT NULL'
        );
    END LOOP;

    q := $q$
SELECT * FROM (
    SELECT $q$ || ARRAY_TO_STRING( select_list, ', ' ) || $q$ FROM $q$ || relation_name || $q$ WHERE ($q$ || criteria || $q$)
)x WHERE $q$ || ARRAY_TO_STRING( where_list, ' AND ' );
    -- RAISE NOTICE 'query: %', q;

    FOR out_record IN EXECUTE q LOOP
        RETURN NEXT out_record;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
DECLARE
    output TEXT;
BEGIN
    EXECUTE $q$
        SELECT  regexp_replace(
                    oils_xpath_string(
                        $q$ || quote_literal($3) || $q$,
                        marc,
                        ' '
                    ),
                    $q$ || quote_literal($4) || $q$,
                    '',
                    'g')
          FROM  $q$ || $1 || $q$
          WHERE id = $q$ || $2 INTO output;
    RETURN output;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION extract_marc_field ( TEXT, BIGINT, TEXT ) RETURNS TEXT AS $$
    SELECT extract_marc_field($1,$2,$3,'');
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
	moved_objects INT := 0;
	source_cn     asset.call_number%ROWTYPE;
	target_cn     asset.call_number%ROWTYPE;
	metarec       metabib.metarecord%ROWTYPE;
	hold          action.hold_request%ROWTYPE;
	ser_rec       serial.record_entry%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN
        
        SELECT  COUNT(*) INTO counter
          FROM  oils_xpath_table(
                    'id',
                    'marc',
                    'biblio.record_entry',
                    '//*[@tag="856"]',
                    'id=' || lineitem
                ) as t(i int,c text);
    
        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim" tag="856">' ||
                        array_to_string(
                            array_accum(
                                '<subfield code="' || subfield || '">' ||
                                regexp_replace(
                                    regexp_replace(
                                        regexp_replace(data,'&','&amp;','g'),
                                        '>', '&gt;', 'g'
                                    ),
                                    '<', '&lt;', 'g'
                                ) || '</subfield>'
                            ), ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  oils_xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,subfield text,data text);

            uri_text := uri_text || uri_datafield;
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

	-- Find and move metarecords to the target record
	SELECT	INTO metarec *
	  FROM	metabib.metarecord
	  WHERE	master_record = source_record;

	IF FOUND THEN
		UPDATE	metabib.metarecord
		  SET	master_record = target_record,
			mods = NULL
		  WHERE	id = metarec.id;

		moved_objects := moved_objects + 1;
	END IF;

	-- Find call numbers attached to the source ...
	FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

		SELECT	INTO target_cn *
		  FROM	asset.call_number
		  WHERE	label = source_cn.label
			AND owning_lib = source_cn.owning_lib
			AND record = target_record;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copies to that, and ...
			UPDATE	asset.copy
			  SET	call_number = target_cn.id
			  WHERE	call_number = source_cn.id;

			-- ... move V holds to the move-target call number
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_cn.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;

		-- ... if not ...
		ELSE
			-- ... just move the call number to the target record
			UPDATE	asset.call_number
			  SET	record = target_record
			  WHERE	id = source_cn.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find T holds targeting the source record ...
	FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

		-- ... and move them to the target record
		UPDATE	action.hold_request
		  SET	target = target_record
		  WHERE	id = hold.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial records targeting the source record ...
	FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.record_entry
		  SET	record = target_record
		  WHERE	id = ser_rec.id;

		moved_objects := moved_objects + 1;
	END LOOP;

    -- Finally, "delete" the source record
    DELETE FROM biblio.record_entry WHERE id = source_record;

	-- That's all, folks!
	RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION vandelay.ingest_items ( import_id BIGINT, attr_def_id BIGINT ) RETURNS SETOF vandelay.import_item AS $$
DECLARE

    owning_lib      TEXT;
    circ_lib        TEXT;
    call_number     TEXT;
    copy_number     TEXT;
    status          TEXT;
    location        TEXT;
    circulate       TEXT;
    deposit         TEXT;
    deposit_amount  TEXT;
    ref             TEXT;
    holdable        TEXT;
    price           TEXT;
    barcode         TEXT;
    circ_modifier   TEXT;
    circ_as_type    TEXT;
    alert_message   TEXT;
    opac_visible    TEXT;
    pub_note        TEXT;
    priv_note       TEXT;

    attr_def        RECORD;
    tmp_attr_set    RECORD;
    attr_set        vandelay.import_item%ROWTYPE;

    xpath           TEXT;

BEGIN

    SELECT * INTO attr_def FROM vandelay.import_item_attr_definition WHERE id = attr_def_id;

    IF FOUND THEN

        attr_set.definition := attr_def.id; 
    
        -- Build the combined XPath
    
        owning_lib :=
            CASE
                WHEN attr_def.owning_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.owning_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.owning_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.owning_lib
            END;
    
        circ_lib :=
            CASE
                WHEN attr_def.circ_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_lib
            END;
    
        call_number :=
            CASE
                WHEN attr_def.call_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.call_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.call_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.call_number
            END;
    
        copy_number :=
            CASE
                WHEN attr_def.copy_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.copy_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.copy_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.copy_number
            END;
    
        status :=
            CASE
                WHEN attr_def.status IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.status ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.status || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.status
            END;
    
        location :=
            CASE
                WHEN attr_def.location IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.location ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.location || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.location
            END;
    
        circulate :=
            CASE
                WHEN attr_def.circulate IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circulate ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circulate || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circulate
            END;
    
        deposit :=
            CASE
                WHEN attr_def.deposit IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit
            END;
    
        deposit_amount :=
            CASE
                WHEN attr_def.deposit_amount IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit_amount ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit_amount || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit_amount
            END;
    
        ref :=
            CASE
                WHEN attr_def.ref IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.ref ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.ref || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.ref
            END;
    
        holdable :=
            CASE
                WHEN attr_def.holdable IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.holdable ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.holdable || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.holdable
            END;
    
        price :=
            CASE
                WHEN attr_def.price IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.price ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.price || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.price
            END;
    
        barcode :=
            CASE
                WHEN attr_def.barcode IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.barcode ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.barcode || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.barcode
            END;
    
        circ_modifier :=
            CASE
                WHEN attr_def.circ_modifier IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_modifier ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_modifier || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_modifier
            END;
    
        circ_as_type :=
            CASE
                WHEN attr_def.circ_as_type IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_as_type ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_as_type || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_as_type
            END;
    
        alert_message :=
            CASE
                WHEN attr_def.alert_message IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.alert_message ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.alert_message || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.alert_message
            END;
    
        opac_visible :=
            CASE
                WHEN attr_def.opac_visible IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.opac_visible ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.opac_visible || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.opac_visible
            END;

        pub_note :=
            CASE
                WHEN attr_def.pub_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.pub_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.pub_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.pub_note
            END;
        priv_note :=
            CASE
                WHEN attr_def.priv_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.priv_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.priv_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.priv_note
            END;
    
    
        xpath := 
            owning_lib      || '|' || 
            circ_lib        || '|' || 
            call_number     || '|' || 
            copy_number     || '|' || 
            status          || '|' || 
            location        || '|' || 
            circulate       || '|' || 
            deposit         || '|' || 
            deposit_amount  || '|' || 
            ref             || '|' || 
            holdable        || '|' || 
            price           || '|' || 
            barcode         || '|' || 
            circ_modifier   || '|' || 
            circ_as_type    || '|' || 
            alert_message   || '|' || 
            pub_note        || '|' || 
            priv_note       || '|' || 
            opac_visible;

        -- RAISE NOTICE 'XPath: %', xpath;
        
        FOR tmp_attr_set IN
                SELECT  *
                  FROM  oils_xpath_table( 'id', 'marc', 'vandelay.queued_bib_record', xpath, 'id = ' || import_id )
                            AS t( id INT, ol TEXT, clib TEXT, cn TEXT, cnum TEXT, cs TEXT, cl TEXT, circ TEXT,
                                  dep TEXT, dep_amount TEXT, r TEXT, hold TEXT, pr TEXT, bc TEXT, circ_mod TEXT,
                                  circ_as TEXT, amessage TEXT, note TEXT, pnote TEXT, opac_vis TEXT )
        LOOP
    
            tmp_attr_set.pr = REGEXP_REPLACE(tmp_attr_set.pr, E'[^0-9\\.]', '', 'g');
            tmp_attr_set.dep_amount = REGEXP_REPLACE(tmp_attr_set.dep_amount, E'[^0-9\\.]', '', 'g');

            tmp_attr_set.pr := NULLIF( tmp_attr_set.pr, '' );
            tmp_attr_set.dep_amount := NULLIF( tmp_attr_set.dep_amount, '' );
    
            SELECT id INTO attr_set.owning_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.ol); -- INT
            SELECT id INTO attr_set.circ_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.clib); -- INT
            SELECT id INTO attr_set.status FROM config.copy_status WHERE LOWER(name) = LOWER(tmp_attr_set.cs); -- INT
    
            SELECT  id INTO attr_set.location
              FROM  asset.copy_location
              WHERE LOWER(name) = LOWER(tmp_attr_set.cl)
                    AND asset.copy_location.owning_lib = COALESCE(attr_set.owning_lib, attr_set.circ_lib); -- INT
    
            attr_set.circulate      :=
                LOWER( SUBSTRING( tmp_attr_set.circ, 1, 1)) IN ('t','y','1')
                OR LOWER(tmp_attr_set.circ) = 'circulating'; -- BOOL

            attr_set.deposit        :=
                LOWER( SUBSTRING( tmp_attr_set.dep, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.dep) = 'deposit'; -- BOOL

            attr_set.holdable       :=
                LOWER( SUBSTRING( tmp_attr_set.hold, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.hold) = 'holdable'; -- BOOL

            attr_set.opac_visible   :=
                LOWER( SUBSTRING( tmp_attr_set.opac_vis, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.opac_vis) = 'visible'; -- BOOL

            attr_set.ref            :=
                LOWER( SUBSTRING( tmp_attr_set.r, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.r) = 'reference'; -- BOOL
    
            attr_set.copy_number    := tmp_attr_set.cnum::INT; -- INT,
            attr_set.deposit_amount := tmp_attr_set.dep_amount::NUMERIC(6,2); -- NUMERIC(6,2),
            attr_set.price          := tmp_attr_set.pr::NUMERIC(8,2); -- NUMERIC(8,2),
    
            attr_set.call_number    := tmp_attr_set.cn; -- TEXT
            attr_set.barcode        := tmp_attr_set.bc; -- TEXT,
            attr_set.circ_modifier  := tmp_attr_set.circ_mod; -- TEXT,
            attr_set.circ_as_type   := tmp_attr_set.circ_as; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.pub_note       := tmp_attr_set.note; -- TEXT,
            attr_set.priv_note      := tmp_attr_set.pnote; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
    
            RETURN NEXT attr_set;
    
        END LOOP;
    
    END IF;

    RETURN;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( rid BIGINT, default_joiner TEXT ) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    raw_text    TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    output_row  metabib.field_entry_template%ROWTYPE;
BEGIN

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field ORDER BY format LOOP

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- RAISE NOTICE 'idx: %, xfrm: %', idx.id, xfrm.name;

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
        output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

        RETURN NEXT output_row;

        -- RAISE NOTICE 'output: %', output_row;

    END LOOP;

    RETURN;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.extract_fingerprint ( marc text ) RETURNS TEXT AS $func$
DECLARE
    idx     config.biblio_fingerprint%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    raw_text    TEXT;
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

        output_text := output_text || REGEXP_REPLACE(raw_text, E'\\s+', '', 'g');

    END LOOP;

    RETURN output_text;

END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

