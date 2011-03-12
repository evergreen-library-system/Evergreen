DROP SCHEMA IF EXISTS unapi CASCADE;

BEGIN;
CREATE SCHEMA unapi;

CREATE OR REPLACE FUNCTION array_remove_item_by_value(inp ANYARRAY, el ANYELEMENT) RETURNS anyarray AS $$ SELECT ARRAY_ACCUM(x.e) FROM UNNEST( $1 ) x(e) WHERE x.e <> $2; $$ LANGUAGE SQL;

CREATE TABLE unapi.bre_output_layout (
    name                TEXT    PRIMARY KEY,
    transform           TEXT    REFERENCES config.xml_transform (name) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    mime_type           TEXT    NOT NULL,
    feed_top            TEXT    NOT NULL,
    holdings_element    TEXT,
    title_element       TEXT,
    description_element TEXT,
    creator_element     TEXT,
    update_ts_element   TEXT
);

INSERT INTO unapi.bre_output_layout
    (name,           transform, mime_type,              holdings_element, feed_top,         title_element, description_element, creator_element, update_ts_element)
        VALUES
    ('holdings_xml', NULL,      'application/xml',      NULL,             'hxml',           NULL,          NULL,                NULL,            NULL),
    ('marcxml',      'marcxml', 'application/marc+xml', 'record',         'collection',     NULL,          NULL,                NULL,            NULL),
    ('mods32',       'mods32',  'application/mods+xml', 'mods',           'modsCollection', NULL,          NULL,                NULL,            NULL)
;

-- Dummy functions, so we can create the real ones out of order
CREATE OR REPLACE FUNCTION unapi.aou    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acn    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.ssub   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sdist  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sstr   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sitem  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sunit  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sisum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sbsum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sssum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.siss   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.auri   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acp    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acpn   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acl    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.ccs    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.bre    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.holdings_xml ( bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.memoize (classname TEXT, obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    key     TEXT;
    output  XML;
BEGIN
    key :=
        'id'        || COALESCE(obj_id::TEXT,'') ||
        'format'    || COALESCE(format::TEXT,'') ||
        'ename'     || COALESCE(ename::TEXT,'') ||
        'includes'   || COALESCE(includes::TEXT,'{}'::TEXT[]::TEXT) ||
        'org'       || COALESCE(org::TEXT,'') ||
        'depth'     || COALESCE(depth::TEXT,'') ||
        'slimit'    || COALESCE(slimit::TEXT,'') ||
        'soffset'   || COALESCE(soffset::TEXT,'');
    -- RAISE NOTICE 'memoize key: %', key;

    key := MD5(key);
    -- RAISE NOTICE 'memoize hash: %', key;

    -- XXX cache logic ... memcached? table?

    EXECUTE $$SELECT unapi.$$ || classname || $$( $1, $2, $3, $4, $5, $6, $7, $8);$$ INTO output USING obj_id, format, ename, includes, org, depth, slimit, soffset;
    RETURN output;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    layout          unapi.bre_output_layout%ROWTYPE;
    transform       config.xml_transform%ROWTYPE;
    item_format     TEXT;
    tmp_xml         TEXT;
    xmlns_uri       TEXT := 'http://open-ils.org/spec/feed-xml/v1';
    ouid            INT;
    element_list    TEXT[];
BEGIN

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;
    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO transform FROM config.xml_transform WHERE name = layout.transform;
    xmlns_uri := COALESCE(transform.namespace_uri,xmlns_uri);

    -- Gather the bib xml
    SELECT XMLAGG( unapi.bre(i, format, '', includes, org, depth, slimit, soffset)) INTO tmp_xml FROM UNNEST( id_list ) i;

    IF layout.title_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.title_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, title;
    END IF;

    IF layout.description_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.description_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, description;
    END IF;

    IF layout.creator_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.creator_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, creator;
    END IF;

    IF layout.update_ts_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.update_ts_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, update_ts;
    END IF;

    IF unapi_url IS NOT NULL THEN
        EXECUTE $$SELECT XMLCONCAT( XMLELEMENT( name link, XMLATTRIBUTES( 'http://www.w3.org/1999/xhtml' AS xmlns, 'unapi-server' AS rel, $1 AS href, 'unapi' AS title)), $2)$$ INTO tmp_xml USING unapi_url, tmp_xml::XML;
    END IF;

    IF header_xml IS NOT NULL THEN tmp_xml := XMLCONCAT(header_xml,tmp_xml::XML); END IF;

    element_list := regexp_split_to_array(layout.feed_top,E'\\.');
    FOR i IN REVERSE ARRAY_UPPER(element_list, 1) .. 1 LOOP
        EXECUTE 'SELECT XMLELEMENT( name '|| quote_ident(element_list[i]) ||', XMLATTRIBUTES( $1 AS xmlns), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML;
    END LOOP;

    RETURN tmp_xml::XML;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.bre ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    me      biblio.record_entry%ROWTYPE;
    layout  unapi.bre_output_layout%ROWTYPE;
    xfrm    config.xml_transform%ROWTYPE;
    ouid    INT;
    tmp_xml TEXT;
    top_el  TEXT;
    output  XML;
    hxml    XML;
BEGIN

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;

    IF ouid IS NULL THEN
        RETURN NULL::XML;
    END IF;

    IF format = 'holdings_xml' THEN -- the special case
        output := unapi.holdings_xml( obj_id, ouid, org, depth, includes, slimit, soffset);
        RETURN output;
    END IF;

    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO xfrm FROM config.xml_transform WHERE name = layout.transform;

    SELECT * INTO me FROM biblio.record_entry WHERE id = obj_id;

    -- grab hodlings if we need them
    IF ('holdings_xml' = ANY (includes)) THEN 
        hxml := unapi.holdings_xml(obj_id, ouid, org, depth, array_remove_item_by_value(includes,'holdings_xml'), slimit, soffset);
    ELSE
        hxml := NULL::XML;
    END IF;


    -- generate our item node


    IF format = 'marcxml' THEN
        tmp_xml := me.marc;
    ELSE
        tmp_xml := oils_xslt_process(me.marc, xfrm.xslt)::XML;
    END IF;

    top_el := REGEXP_REPLACE(tmp_xml, E'^.*?<((?:\\S+:)?' || layout.holdings_element || ').*$', E'\\1');

    IF hxml IS NOT NULL THEN -- XXX how do we configure the holdings position?
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', hxml || '</' || top_el || E'>\\1');
    END IF;

    IF ('bre.unapi' = ANY (includes)) THEN 
        output := REGEXP_REPLACE(
            tmp_xml,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name abbr,
                XMLATTRIBUTES(
                    'http://www.w3.org/1999/xhtml' AS xmlns,
                    'unapi-id' AS class,
                    'tag:open-ils.org:U2@bre/' || obj_id || '/' || org AS title
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := tmp_xml;
    END IF;

    RETURN output;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL) RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    'http://open-ils.org/spec/holdings/v1' AS xmlns,
                    CASE WHEN ('bre' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id
                 ),
                 XMLELEMENT(
                     name counts,
                     (SELECT  XMLAGG(XMLELEMENT::XML) FROM (
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($2,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_ou_record_copy_count($2, $1)
                                     ORDER BY 1
                     )x)
                 ),
                 CASE WHEN ('acn' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 
                     XMLELEMENT(
                         name volumes,
                         (SELECT XMLAGG(acn) FROM (
                            SELECT  unapi.acn(acn.id,'xml','volume',array_remove_item_by_value(array_remove_item_by_value('{acn,auri}'::TEXT[] || $5,'holdings_xml'),'bre'), $3, $4, $6, $7)
                              FROM  asset.call_number acn
                              WHERE acn.record = $1
                                    AND EXISTS (
                                        SELECT  1
                                          FROM  asset.copy acp
                                                JOIN actor.org_unit_descendants(
                                                    $2,
                                                    (COALESCE(
                                                        $4,
                                                        (SELECT aout.depth
                                                          FROM  actor.org_unit_type aout
                                                                JOIN actor.org_unit aou ON (aou.ou_type = aout.id AND aou.id = $2)
                                                        )
                                                    ))
                                                ) aoud ON (acp.circ_lib = aoud.id)
                                          LIMIT 1
                                    )
                              ORDER BY label_sortkey
                              LIMIT $6
                              OFFSET $7
                         )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('ssub' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7)
                              FROM  serial.subscription
                              WHERE record_entry = $1
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.ssub ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name subscription,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@ssub/' || id AS id,
                        start_date AS start, end_date AS end, expected_date_offset
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', array_remove_item_by_value($4,'ssub'), $5, $6, $7, $8),
                    XMLELEMENT( name distributions,
                        CASE 
                            WHEN ('sdist' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sdist( id, 'xml', 'distribution', array_remove_item_by_value($4,'ssub'), $5, $6, $7, $8) FROM serial.distribution WHERE subscription = ssub.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.subscription ssub
          WHERE id = $1
          GROUP BY id, start_date, end_date, expected_date_offset, owning_lib;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sdist ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name distribution,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@sdist/' || id AS id,
			'tag:open-ils.org:U2@acn/' || receive_call_number AS receive_call_number,
			'tag:open-ils.org:U2@acn/' || bind_call_number AS bind_call_number,
                        unit_label_prefix, label, unit_label_suffix, summary_method
                    ),
                    unapi.aou( holding_lib, $2, 'holding_lib', array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8),
                    CASE WHEN subscription IS NOT NULL AND ('ssub' = ANY ($4)) THEN unapi.ssub( subscription, 'xml', 'subscription', array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8) ELSE NULL END,
                    XMLELEMENT( name streams,
                        CASE 
                            WHEN ('sstr' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sstr( id, 'xml', 'stream', array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8) FROM serial.stream WHERE distribution = sdist.id))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name summaries,
                        CASE 
                            WHEN ('ssum' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sbsum( id, 'xml', 'serial_summary', array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8) FROM serial.basic_summary WHERE distribution = sdist.id))
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('ssum' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sisum( id, 'xml', 'serial_summary', array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8) FROM serial.index_summary WHERE distribution = sdist.id))
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('ssum' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sssum( id, 'xml', 'serial_summary', array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8) FROM serial.supplement_summary WHERE distribution = sdist.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.distribution sdist
          WHERE id = $1
          GROUP BY id, label, unit_label_prefix, unit_label_suffix, holding_lib, summary_method, subscription, receive_call_number, bind_call_number;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sstr ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name stream,
                XMLATTRIBUTES(
                    'http://open-ils.org/spec/holdings/v1' AS xmlns,
                    'tag:open-ils.org:U2@sstr/' || id AS id,
                    routing_label
                ),
                CASE WHEN distribution IS NOT NULL AND ('sdist' = ANY ($4)) THEN unapi.sssum( distribution, 'xml', 'distribtion', array_remove_item_by_value($4,'sstr'), $5, $6, $7, $8) ELSE NULL END,
                XMLELEMENT( name items,
                    CASE 
                        WHEN ('sitem' = ANY ($4)) THEN
                            XMLAGG((SELECT unapi.sitem( id, 'xml', 'serial_item', array_remove_item_by_value($4,'sstr'), $5, $6, $7, $8) FROM serial.item WHERE stream = sstr.id))
                        ELSE NULL
                    END
                )
            )
      FROM  serial.stream sstr
      WHERE id = $1
      GROUP BY id, routing_label, distribution;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.siss ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name issuance,
                XMLATTRIBUTES(
                    'http://open-ils.org/spec/holdings/v1' AS xmlns,
                    'tag:open-ils.org:U2@siss/' || id AS id,
                    create_date, edit_date, label, date_published,
                    holding_code, holding_type, holding_link_id
                ),
                CASE WHEN subscription IS NOT NULL AND ('ssub' = ANY ($4)) THEN unapi.ssub( subscription, 'xml', 'subscription', array_remove_item_by_value($4,'siss'), $5, $6, $7, $8) ELSE NULL END,
                XMLELEMENT( name items,
                    CASE 
                        WHEN ('sitem' = ANY ($4)) THEN
                            XMLAGG((SELECT unapi.sitem( id, 'xml', 'serial_item', array_remove_item_by_value($4,'siss'), $5, $6, $7, $8) FROM serial.item WHERE issuance = sstr.id))
                        ELSE NULL
                    END
                )
            )
      FROM  serial.issuance sstr
      WHERE id = $1
      GROUP BY id, create_date, edit_date, label, date_published, holding_code, holding_type, holding_link_id, subscription;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sitem ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_item,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@sitem/' || id AS id,
                        'tag:open-ils.org:U2@siss/' || issuance AS issuance,
                        date_expected, date_received
                    ),
                    CASE WHEN issuance IS NOT NULL AND ('siss' = ANY ($4)) THEN unapi.siss( issuance, $2, 'issuance', array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8) ELSE NULL END,
                    CASE WHEN stream IS NOT NULL AND ('sstr' = ANY ($4)) THEN unapi.sstr( stream, $2, 'stream', array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8) ELSE NULL END,
                    CASE WHEN unit IS NOT NULL AND ('sunit' = ANY ($4)) THEN unapi.sunit( stream, $2, 'serial_unit', array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8) ELSE NULL END,
                    CASE WHEN uri IS NOT NULL AND ('auri' = ANY ($4)) THEN unapi.auri( uri, $2, 'uri', array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8) ELSE NULL END
--                    XMLELEMENT( name notes,
--                        CASE 
--                            WHEN ('acpn' = ANY ($4)) THEN
--                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
--                            ELSE NULL
--                        END
--                    )
                )
          FROM  serial.item sitem
          WHERE id = $1;
$F$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION unapi.sssum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    'http://open-ils.org/spec/holdings/v1' AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sssum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', array_remove_item_by_value($4,'ssum'), $5, $6, $7, $8) ELSE NULL END
            )
      FROM  serial.supplement_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sbsum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    'http://open-ils.org/spec/holdings/v1' AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sbsum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', array_remove_item_by_value($4,'ssum'), $5, $6, $7, $8) ELSE NULL END
            )
      FROM  serial.basic_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sisum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    'http://open-ils.org/spec/holdings/v1' AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sisum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', array_remove_item_by_value($4,'ssum'), $5, $6, $7, $8) ELSE NULL END
            )
      FROM  serial.index_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION unapi.aou ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    output XML;
BEGIN
    IF ename = 'circlib' THEN
        SELECT  XMLELEMENT(
                    name circlib,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/actors/v1' AS xmlns,
                        id AS ident
                    ),
                    name
                ) INTO output
          FROM  actor.org_unit aou
          WHERE id = obj_id;
    ELSE
        EXECUTE $$SELECT  XMLELEMENT(
                    name $$ || ename || $$,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/actors/v1' AS xmlns,
                        'tag:open-ils.org:U2@aou/' || id AS id,
                        shortname, name, opac_visible
                    )
                )
          FROM  actor.org_unit aou
         WHERE id = $1 $$ INTO output USING obj_id;
    END IF;

    RETURN output;

END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.acl ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name location,
                XMLATTRIBUTES(
                    'http://open-ils.org/spec/holdings/v1' AS xmlns,
                    id AS ident
                ),
                name
            )
      FROM  asset.copy_location
      WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.ccs ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name status,
                XMLATTRIBUTES(
                    'http://open-ils.org/spec/holdings/v1' AS xmlns,
                    id AS ident
                ),
                name
            )
      FROM  config.copy_status
      WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acpn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy_note,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        create_date AS date,
                        title
                    ),
                    value
                )
          FROM  asset.copy_note
          WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name statcat,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        sc.name,
                        sc.opac_visible
                    ),
                    asce.value
                )
          FROM  asset.stat_cat_entry asce
                JOIN asset.stat_cat sc ON (sc.id = asce.stat_cat)
          WHERE asce.id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible
                    ),
                    unapi.ccs( status, $2, 'status', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.acl( location, $2, 'location', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circ_lib', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE 
                            WHEN ('acpn' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE 
                            WHEN ('ascecm' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( stat_cat_entry, 'xml', 'statcat', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) FROM asset.stat_cat_entry_copy_map WHERE owning_copy = cp.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  asset.copy cp
          WHERE id = $1
          GROUP BY id, status, location, circ_lib, call_number, create_date, edit_date, copy_number, circulate, deposit, ref, holdable, deleted, deposit_amount, price, barcode, circ_modifier, circ_as_type, opac_visible;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sunit ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_unit,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible, status_changed_time,
                        floating, mint_condition, detailed_contents, sort_key, summary_contents, cost 
                    ),
                    unapi.ccs( status, $2, 'status', array_remove_item_by_value(array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    unapi.acl( location, $2, 'location', array_remove_item_by_value(array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circ_lib', array_remove_item_by_value(array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', array_remove_item_by_value(array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE 
                            WHEN ('acpn' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', array_remove_item_by_value(array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE 
                            WHEN ('ascecm' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( stat_cat_entry, 'xml', 'statcat', array_remove_item_by_value(array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8) FROM asset.stat_cat_entry_copy_map WHERE owning_copy = cp.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.unit cp
          WHERE id = $1
          GROUP BY  id, status, location, circ_lib, call_number, create_date, edit_date, copy_number, circulate, floating, mint_condition,
                    deposit, ref, holdable, deleted, deposit_amount, price, barcode, circ_modifier, circ_as_type, opac_visible, status_changed_time, detailed_contents, sort_key, summary_contents, cost;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@acn/' || acn.id AS id,
                        o.shortname AS lib,
                        o.opac_visible AS opac_visible,
                        deleted, label, label_sortkey, label_class, record
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8),
                    XMLELEMENT( name copies,
                        CASE 
                            WHEN ('acp' = ANY ($4)) THEN
                                (SELECT XMLAGG(acp) FROM (
                                    SELECT  unapi.acp( cp.id, 'xml', 'copy', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8)
                                      FROM  asset.copy cp
                                            JOIN actor.org_unit_descendants(
                                                (SELECT id FROM actor.org_unit WHERE shortname = $5),
                                                (COALESCE($6,(SELECT aout.depth FROM actor.org_unit_type aout JOIN actor.org_unit aou ON (aou.ou_type = aout.id AND aou.shortname = $5))))
                                            ) aoud ON (cp.circ_lib = aoud.id)
                                      WHERE cp.call_number = acn.id
                                      ORDER BY COALESCE(cp.copy_number,0), cp.barcode
                                      LIMIT $7
                                      OFFSET $8
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT(
                        name uris,
                        (SELECT XMLAGG(auri) FROM (SELECT unapi.auri(uri,'xml','uri', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8) FROM asset.uri_call_number_map WHERE call_number = acn.id)x)
                    ),
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( acn.record, 'marcxml', 'record', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8) ELSE NULL END
                ) AS x
          FROM  asset.call_number acn
                JOIN actor.org_unit o ON (o.id = acn.owning_lib)
          WHERE acn.id = $1
          GROUP BY acn.id, o.shortname, o.opac_visible, deleted, label, label_sortkey, label_class, owning_lib, record;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.auri ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@auri/' || uri.id AS id,
                        use_restriction,
                        href,
                        label
                    ),
                    XMLELEMENT( name copies,
                        CASE 
                            WHEN ('acn' = ANY ($4)) THEN
                                (SELECT XMLAGG(acn) FROM (SELECT unapi.acn( call_number, 'xml', 'copy', array_remove_item_by_value($4,'auri'), $5, $6, $7, $8) FROM asset.uri_call_number_map WHERE uri = uri.id)x)
                            ELSE NULL
                        END
                    )
                ) AS x
          FROM  asset.uri uri
          WHERE uri.id = $1
          GROUP BY uri.id, use_restriction, href, label;
$F$ LANGUAGE SQL;

/*

 -- Some test queries

SELECT unapi.memoize( 'bre', 1,'mods32','','{holdings_xml,acp}'::TEXT[], 'SYS1');
SELECT unapi.memoize( 'bre', 1,'marcxml','','{holdings_xml,acp}'::TEXT[], 'SYS1');
SELECT unapi.memoize( 'bre', 1,'holdings_xml','','{holdings_xml,acp}'::TEXT[], 'SYS1');

SELECT unapi.biblio_record_entry_feed('{1}'::BIGINT[],'mods32','{holdings_xml,acp}'::TEXT[],'SYS1',NULL,1,NULL, NULL,NULL,NULL,NULL,'http://c64/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');

SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'marcxml','{}'::TEXT[],'SYS1',NULL,1,NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');
EXPLAIN ANALYZE SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'marcxml','{}'::TEXT[],'SYS1',NULL,1,NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');
EXPLAIN ANALYZE SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'marcxml','{holdings_xml}'::TEXT[],'SYS1',NULL,1,NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');
EXPLAIN ANALYZE SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'mods32','{holdings_xml}'::TEXT[],'SYS1',NULL,1,NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');

SELECT unapi.biblio_record_entry_feed('{216}'::BIGINT[],'marcxml','{}'::TEXT[], 'BR1');
EXPLAIN ANALYZE SELECT unapi.bre(216,'marcxml','record','{holdings_xml,bre.unapi}'::TEXT[], 'BR1');
EXPLAIN ANALYZE SELECT unapi.bre(216,'holdings_xml','record','{}'::TEXT[], 'BR1');
EXPLAIN ANALYZE SELECT unapi.holdings_xml(216,4,'BR1',2,'{bre}'::TEXT[]);
EXPLAIN ANALYZE SELECT unapi.bre(216,'mods32','record','{}'::TEXT[], 'BR1');

*/

COMMIT;

