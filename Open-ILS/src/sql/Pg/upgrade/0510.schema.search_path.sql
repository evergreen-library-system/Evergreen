BEGIN;

INSERT INTO config.upgrade_log('0510'); -- miker

SELECT evergreen.change_db_setting('search_path', ARRAY['evergreen','public','pg_catalog']);

-- Fix function breakage due to short search path
CREATE OR REPLACE FUNCTION evergreen.force_unicode_normal_form(string TEXT, form TEXT) RETURNS TEXT AS $func$
use Unicode::Normalize 'normalize';
return normalize($_[1],$_[0]); # reverse the params
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.facet_force_nfc() RETURNS TRIGGER AS $$
BEGIN
    NEW.value := force_unicode_normal_form(NEW.value,'NFC');
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

DROP TRIGGER facet_force_nfc_tgr ON metabib.facet_entry;

CREATE TRIGGER facet_force_nfc_tgr
    BEFORE UPDATE OR INSERT ON metabib.facet_entry
    FOR EACH ROW EXECUTE PROCEDURE evergreen.facet_force_nfc();

DROP FUNCTION IF EXISTS public.force_unicode_normal_form (TEXT,TEXT);
DROP FUNCTION IF EXISTS public.facet_force_nfc ();

CREATE OR REPLACE FUNCTION evergreen.xml_escape(str TEXT) RETURNS text AS $$
    SELECT REPLACE(REPLACE(REPLACE($1,
       '&', '&amp;'),
       '<', '&lt;'),
       '>', '&gt;');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.maintain_901 () RETURNS TRIGGER AS $func$
DECLARE
    use_id_for_tcn BOOLEAN;
BEGIN
    -- Remove any existing 901 fields before we insert the authoritative one
    NEW.marc := REGEXP_REPLACE(NEW.marc, E'<datafield[^>]*?tag="901".+?</datafield>', '', 'g');

    IF TG_TABLE_SCHEMA = 'biblio' THEN
        -- Set TCN value to record ID?
        SELECT enabled FROM config.global_flag INTO use_id_for_tcn
            WHERE name = 'cat.bib.use_id_for_tcn';

        IF use_id_for_tcn = 't' THEN
            NEW.tcn_value := NEW.id;
        END IF;

        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="a">' || evergreen.xml_escape(NEW.tcn_value) || E'</subfield>' ||
                '<subfield code="b">' || evergreen.xml_escape(NEW.tcn_source) || E'</subfield>' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                CASE WHEN NEW.owner IS NOT NULL THEN '<subfield code="o">' || NEW.owner || E'</subfield>' ELSE '' END ||
                CASE WHEN NEW.share_depth IS NOT NULL THEN '<subfield code="d">' || NEW.share_depth || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'authority' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'serial' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                '<subfield code="o">' || NEW.owning_lib || E'</subfield>' ||
                CASE WHEN NEW.record IS NOT NULL THEN '<subfield code="r">' || NEW.record || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSE
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

DROP TRIGGER b_maintain_901 ON biblio.record_entry;
DROP TRIGGER b_maintain_901 ON authority.record_entry;
DROP TRIGGER b_maintain_901 ON serial.record_entry;

CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_901();
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_901();
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON serial.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_901();

DROP FUNCTION IF EXISTS public.maintain_901 ();

------ Backporting note: 2.1+ only beyond here --------

DROP SCHEMA IF EXISTS unapi CASCADE;
CREATE SCHEMA unapi;

CREATE OR REPLACE FUNCTION evergreen.array_remove_item_by_value(inp ANYARRAY, el ANYELEMENT) RETURNS anyarray AS $$ SELECT ARRAY_ACCUM(x.e) FROM UNNEST( $1 ) x(e) WHERE x.e <> $2; $$ LANGUAGE SQL;

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
CREATE OR REPLACE FUNCTION unapi.aou    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acnp   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acns   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acn    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.ssub   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sdist  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sstr   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sitem  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sunit  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sisum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sbsum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sssum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.siss   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.auri   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acp    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acpn   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acl    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.ccs    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.bre    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.bmp    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.holdings_xml ( bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.memoize (classname TEXT, obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
DECLARE
    key     TEXT;
    output  XML;
BEGIN
    key :=
        'id'        || COALESCE(obj_id::TEXT,'') ||
        'format'    || COALESCE(format::TEXT,'') ||
        'ename'     || COALESCE(ename::TEXT,'') ||
        'includes'  || COALESCE(includes::TEXT,'{}'::TEXT[]::TEXT) ||
        'org'       || COALESCE(org::TEXT,'') ||
        'depth'     || COALESCE(depth::TEXT,'') ||
        'slimit'    || COALESCE(slimit::TEXT,'') ||
        'soffset'   || COALESCE(soffset::TEXT,'') ||
        'include_xmlns'   || COALESCE(include_xmlns::TEXT,'');
    -- RAISE NOTICE 'memoize key: %', key;

    key := MD5(key);
    -- RAISE NOTICE 'memoize hash: %', key;

    -- XXX cache logic ... memcached? table?

    EXECUTE $$SELECT unapi.$$ || classname || $$( $1, $2, $3, $4, $5, $6, $7, $8, $9);$$ INTO output USING obj_id, format, ename, includes, org, depth, slimit, soffset, include_xmlns;
    RETURN output;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$
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
    SELECT XMLAGG( unapi.bre(i, format, '', includes, org, depth, slimit, soffset, include_xmlns)) INTO tmp_xml FROM UNNEST( id_list ) i;

    IF layout.title_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.title_element ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, title, include_xmlns;
    END IF;

    IF layout.description_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.description_element ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, description, include_xmlns;
    END IF;

    IF layout.creator_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.creator_element ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, creator, include_xmlns;
    END IF;

    IF layout.update_ts_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.update_ts_element ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, update_ts, include_xmlns;
    END IF;

    IF unapi_url IS NOT NULL THEN
        EXECUTE $$SELECT XMLCONCAT( XMLELEMENT( name link, XMLATTRIBUTES( 'http://www.w3.org/1999/xhtml' AS xmlns, 'unapi-server' AS rel, $1 AS href, 'unapi' AS title)), $2)$$ INTO tmp_xml USING unapi_url, tmp_xml::XML;
    END IF;

    IF header_xml IS NOT NULL THEN tmp_xml := XMLCONCAT(header_xml,tmp_xml::XML); END IF;

    element_list := regexp_split_to_array(layout.feed_top,E'\\.');
    FOR i IN REVERSE ARRAY_UPPER(element_list, 1) .. 1 LOOP
        EXECUTE 'SELECT XMLELEMENT( name '|| quote_ident(element_list[i]) ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, include_xmlns;
    END LOOP;

    RETURN tmp_xml::XML;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.bre ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
        output := unapi.holdings_xml( obj_id, ouid, org, depth, includes, slimit, soffset, include_xmlns);
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
        hxml := unapi.holdings_xml(obj_id, ouid, org, depth, evergreen.array_remove_item_by_value(includes,'holdings_xml'), slimit, soffset, include_xmlns);
    ELSE
        hxml := NULL::XML;
    END IF;


    -- generate our item node


    IF format = 'marcxml' THEN
        tmp_xml := me.marc;
        IF tmp_xml !~ E'<marc:' THEN -- If we're not using the prefixed namespace in this record, then remove all declarations of it
           tmp_xml := REGEXP_REPLACE(tmp_xml, ' xmlns:marc="http://www.loc.gov/MARC21/slim"', '', 'g');
        END IF; 
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

CREATE OR REPLACE FUNCTION unapi.holdings_xml (bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE) RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
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
                 CASE 
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT( name monograph_parts,
                            XMLAGG((SELECT unapi.bmp( id, 'xml', 'monograph_part', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE) FROM biblio.monograph_part WHERE record = $1))
                        )
                     ELSE NULL
                 END,
                 CASE WHEN ('acn' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 
                     XMLELEMENT(
                         name volumes,
                         (SELECT XMLAGG(acn) FROM (
                            SELECT  unapi.acn(acn.id,'xml','volume', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value('{acn,auri}'::TEXT[] || $5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE)
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
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry = $1
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.ssub ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name subscription,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@ssub/' || id AS id,
                        start_date AS start, end_date AS end, expected_date_offset
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'ssub'), $5, $6, $7, $8),
                    XMLELEMENT( name distributions,
                        CASE 
                            WHEN ('sdist' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sdist( id, 'xml', 'distribution', evergreen.array_remove_item_by_value($4,'ssub'), $5, $6, $7, $8, FALSE) FROM serial.distribution WHERE subscription = ssub.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.subscription ssub
          WHERE id = $1
          GROUP BY id, start_date, end_date, expected_date_offset, owning_lib;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sdist ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name distribution,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@sdist/' || id AS id,
			'tag:open-ils.org:U2@acn/' || receive_call_number AS receive_call_number,
			'tag:open-ils.org:U2@acn/' || bind_call_number AS bind_call_number,
                        unit_label_prefix, label, unit_label_suffix, summary_method
                    ),
                    unapi.aou( holding_lib, $2, 'holding_lib', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8),
                    CASE WHEN subscription IS NOT NULL AND ('ssub' = ANY ($4)) THEN unapi.ssub( subscription, 'xml', 'subscription', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name streams,
                        CASE 
                            WHEN ('sstr' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sstr( id, 'xml', 'stream', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) FROM serial.stream WHERE distribution = sdist.id))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name summaries,
                        CASE 
                            WHEN ('ssum' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sbsum( id, 'xml', 'serial_summary', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) FROM serial.basic_summary WHERE distribution = sdist.id))
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('ssum' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sisum( id, 'xml', 'serial_summary', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) FROM serial.index_summary WHERE distribution = sdist.id))
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('ssum' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sssum( id, 'xml', 'serial_summary', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) FROM serial.supplement_summary WHERE distribution = sdist.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.distribution sdist
          WHERE id = $1
          GROUP BY id, label, unit_label_prefix, unit_label_suffix, holding_lib, summary_method, subscription, receive_call_number, bind_call_number;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sstr ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name stream,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sstr/' || id AS id,
                    routing_label
                ),
                CASE WHEN distribution IS NOT NULL AND ('sdist' = ANY ($4)) THEN unapi.sssum( distribution, 'xml', 'distribtion', evergreen.array_remove_item_by_value($4,'sstr'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                XMLELEMENT( name items,
                    CASE 
                        WHEN ('sitem' = ANY ($4)) THEN
                            XMLAGG((SELECT unapi.sitem( id, 'xml', 'serial_item', evergreen.array_remove_item_by_value($4,'sstr'), $5, $6, $7, $8, FALSE) FROM serial.item WHERE stream = sstr.id))
                        ELSE NULL
                    END
                )
            )
      FROM  serial.stream sstr
      WHERE id = $1
      GROUP BY id, routing_label, distribution;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.siss ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name issuance,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@siss/' || id AS id,
                    create_date, edit_date, label, date_published,
                    holding_code, holding_type, holding_link_id
                ),
                CASE WHEN subscription IS NOT NULL AND ('ssub' = ANY ($4)) THEN unapi.ssub( subscription, 'xml', 'subscription', evergreen.array_remove_item_by_value($4,'siss'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                XMLELEMENT( name items,
                    CASE 
                        WHEN ('sitem' = ANY ($4)) THEN
                            XMLAGG((SELECT unapi.sitem( id, 'xml', 'serial_item', evergreen.array_remove_item_by_value($4,'siss'), $5, $6, $7, $8, FALSE) FROM serial.item WHERE issuance = sstr.id))
                        ELSE NULL
                    END
                )
            )
      FROM  serial.issuance sstr
      WHERE id = $1
      GROUP BY id, create_date, edit_date, label, date_published, holding_code, holding_type, holding_link_id, subscription;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sitem ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_item,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@sitem/' || id AS id,
                        'tag:open-ils.org:U2@siss/' || issuance AS issuance,
                        date_expected, date_received
                    ),
                    CASE WHEN issuance IS NOT NULL AND ('siss' = ANY ($4)) THEN unapi.siss( issuance, $2, 'issuance', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN stream IS NOT NULL AND ('sstr' = ANY ($4)) THEN unapi.sstr( stream, $2, 'stream', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN unit IS NOT NULL AND ('sunit' = ANY ($4)) THEN unapi.sunit( stream, $2, 'serial_unit', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN uri IS NOT NULL AND ('auri' = ANY ($4)) THEN unapi.auri( uri, $2, 'uri', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END
--                    XMLELEMENT( name notes,
--                        CASE 
--                            WHEN ('acpn' = ANY ($4)) THEN
--                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
--                            ELSE NULL
--                        END
--                    )
                )
          FROM  serial.item sitem
          WHERE id = $1;
$F$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION unapi.sssum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sssum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', evergreen.array_remove_item_by_value($4,'ssum'), $5, $6, $7, $8, FALSE) ELSE NULL END
            )
      FROM  serial.supplement_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sbsum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sbsum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', evergreen.array_remove_item_by_value($4,'ssum'), $5, $6, $7, $8, FALSE) ELSE NULL END
            )
      FROM  serial.basic_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sisum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sisum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', evergreen.array_remove_item_by_value($4,'ssum'), $5, $6, $7, $8, FALSE) ELSE NULL END
            )
      FROM  serial.index_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION unapi.aou ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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

CREATE OR REPLACE FUNCTION unapi.acl ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name location,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident
                ),
                name
            )
      FROM  asset.copy_location
      WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.ccs ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name status,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident
                ),
                name
            )
      FROM  config.copy_status
      WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acpn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy_note,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        create_date AS date,
                        title
                    ),
                    value
                )
          FROM  asset.copy_note
          WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name statcat,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        sc.name,
                        sc.opac_visible
                    ),
                    asce.value
                )
          FROM  asset.stat_cat_entry asce
                JOIN asset.stat_cat sc ON (sc.id = asce.stat_cat)
          WHERE asce.id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.bmp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name monograph_part,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@bmp/' || id AS id,
                        id AS ident,
                        label,
                        label_sortkey,
                        'tag:open-ils.org:U2@bre/' || record AS record
                    ),
                    CASE 
                        WHEN ('acp' = ANY ($4)) THEN
                            XMLELEMENT( name copies,
                                (SELECT XMLAGG(acp) FROM (
                                    SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'bmp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy cp
                                            JOIN asset.copy_part_map cpm ON (cpm.target_copy = cp.id)
                                      WHERE cpm.part = $1
                                      ORDER BY COALESCE(cp.copy_number,0), cp.barcode
                                      LIMIT $7
                                      OFFSET $8
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( record, 'marcxml', 'record', evergreen.array_remove_item_by_value($4,'bmp'), $5, $6, $7, $8, FALSE) ELSE NULL END
                )
          FROM  biblio.monograph_part
          WHERE id = $1
          GROUP BY id, label, label_sortkey, record;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible
                    ),
                    unapi.ccs( status, $2, 'status', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE 
                            WHEN ('acpn' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE 
                            WHEN ('ascecm' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.ascecm( stat_cat_entry, 'xml', 'statcat', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.stat_cat_entry_copy_map WHERE owning_copy = cp.id))
                            ELSE NULL
                        END
                    ),
                    CASE 
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                XMLAGG((SELECT unapi.bmp( part, 'xml', 'monograph_part', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.copy_part_map WHERE target_copy = cp.id))
                            )
                        ELSE NULL
                    END
                )
          FROM  asset.copy cp
          WHERE id = $1
          GROUP BY id, status, location, circ_lib, call_number, create_date, edit_date, copy_number, circulate, deposit, ref, holdable, deleted, deposit_amount, price, barcode, circ_modifier, circ_as_type, opac_visible;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sunit ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_unit,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible, status_changed_time,
                        floating, mint_condition, detailed_contents, sort_key, summary_contents, cost 
                    ),
                    unapi.ccs( status, $2, 'status', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE 
                            WHEN ('acpn' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE 
                            WHEN ('ascecm' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( stat_cat_entry, 'xml', 'statcat', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE) FROM asset.stat_cat_entry_copy_map WHERE owning_copy = cp.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.unit cp
          WHERE id = $1
          GROUP BY  id, status, location, circ_lib, call_number, create_date, edit_date, copy_number, circulate, floating, mint_condition,
                    deposit, ref, holdable, deleted, deposit_amount, price, barcode, circ_modifier, circ_as_type, opac_visible, status_changed_time, detailed_contents, sort_key, summary_contents, cost;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acn/' || acn.id AS id,
                        o.shortname AS lib,
                        o.opac_visible AS opac_visible,
                        deleted, label, label_sortkey, label_class, record
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8),
                    XMLELEMENT( name copies,
                        CASE 
                            WHEN ('acp' = ANY ($4)) THEN
                                (SELECT XMLAGG(acp) FROM (
                                    SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE)
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
                        (SELECT XMLAGG(auri) FROM (SELECT unapi.auri(uri,'xml','uri', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE call_number = acn.id)x)
                    ),
                    CASE WHEN ('acnp' = ANY ($4)) THEN unapi.acnp( acn.prefix, 'marcxml', 'prefix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN ('acns' = ANY ($4)) THEN unapi.acns( acn.suffix, 'marcxml', 'suffix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( acn.record, 'marcxml', 'record', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END
                ) AS x
          FROM  asset.call_number acn
                JOIN actor.org_unit o ON (o.id = acn.owning_lib)
          WHERE acn.id = $1
          GROUP BY acn.id, o.shortname, o.opac_visible, deleted, label, label_sortkey, label_class, owning_lib, record, acn.prefix, acn.suffix;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acnp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_prefix,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        id AS ident,
                        label,
                        label_sortkey
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'acnp'), $5, $6, $7, $8)
                )
          FROM  asset.call_number_prefix
          WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acns ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_suffix,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        id AS ident,
                        label,
                        label_sortkey
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'acns'), $5, $6, $7, $8)
                )
          FROM  asset.call_number_suffix
          WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.auri ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@auri/' || uri.id AS id,
                        use_restriction,
                        href,
                        label
                    ),
                    XMLELEMENT( name copies,
                        CASE 
                            WHEN ('acn' = ANY ($4)) THEN
                                (SELECT XMLAGG(acn) FROM (SELECT unapi.acn( call_number, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'auri'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE uri = uri.id)x)
                            ELSE NULL
                        END
                    )
                ) AS x
          FROM  asset.uri uri
          WHERE uri.id = $1
          GROUP BY uri.id, use_restriction, href, label;
$F$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS public.array_remove_item_by_value(ANYARRAY,ANYELEMENT);

CREATE OR REPLACE FUNCTION evergreen.lpad_number_substrings( TEXT, TEXT, INT ) RETURNS TEXT AS $$
    my $string = shift;
    my $pad = shift;
    my $len = shift;
    my $find = $len - 1;

    while ($string =~ /(?:^|\D)(\d{1,$find})(?:$|\D)/) {
        my $padded = $1;
        $padded = $pad x ($len - length($padded)) . $padded;
        $string =~ s/$1/$padded/sg;
    }

    return $string;
$$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION biblio.normalize_biblio_monograph_part_sortkey () RETURNS TRIGGER AS $$
BEGIN
    NEW.label_sortkey := REGEXP_REPLACE(
        evergreen.lpad_number_substrings(
            naco_normalize(NEW.label),
            '0',
            10
        ),
        E'\\s+',
        '',
        'g'
    );
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.normalize_affix_sortkey () RETURNS TRIGGER AS $$
BEGIN
    NEW.label_sortkey := REGEXP_REPLACE(
        evergreen.lpad_number_substrings(
            naco_normalize(NEW.label),
            '0',
            10
        ),
        E'\\s+',
        '',
        'g'
    );
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS public.lpad_number_substrings(TEXT,TEXT,INT);

COMMIT;

