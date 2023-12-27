DROP SCHEMA IF EXISTS unapi CASCADE;

BEGIN;
CREATE SCHEMA unapi;

CREATE OR REPLACE FUNCTION evergreen.org_top()
RETURNS actor.org_unit AS $$
    SELECT * FROM actor.org_unit WHERE parent_ou IS NULL LIMIT 1;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.rank_ou(lib INT, search_lib INT, pref_lib INT DEFAULT NULL)
RETURNS INTEGER AS $$
    SELECT COALESCE(

        -- lib matches search_lib
        (SELECT CASE WHEN $1 = $2 THEN -20000 END),

        -- lib matches pref_lib
        (SELECT CASE WHEN $1 = $3 THEN -10000 END),


        -- pref_lib is a child of search_lib and lib is a child of pref lib.  
        -- For example, searching CONS, pref lib is SYS1, 
        -- copies at BR1 and BR2 sort to the front.
        (SELECT distance - 5000
            FROM actor.org_unit_descendants_distance($3) 
            WHERE id = $1 AND $3 IN (
                SELECT id FROM actor.org_unit_descendants($2))),

        -- lib is a child of search_lib
        (SELECT distance FROM actor.org_unit_descendants_distance($2) WHERE id = $1),

        -- all others pay cash
        1000
    );
$$ LANGUAGE SQL STABLE;

-- geolocation-aware variant
CREATE OR REPLACE FUNCTION evergreen.rank_ou(lib INT, search_lib INT, pref_lib INT, plat FLOAT, plon FLOAT)
RETURNS INTEGER AS $$
    SELECT COALESCE(

        -- lib matches search_lib
        (SELECT CASE WHEN $1 = $2 THEN -20000 END),

        -- lib matches pref_lib
        (SELECT CASE WHEN $1 = $3 THEN -10000 END),


        -- pref_lib is a child of search_lib and lib is a child of pref lib.  
        -- For example, searching CONS, pref lib is SYS1, 
        -- copies at BR1 and BR2 sort to the front.
        (SELECT distance - 5000
            FROM actor.org_unit_descendants_distance($3) 
            WHERE id = $1 AND $3 IN (
                SELECT id FROM actor.org_unit_descendants($2))),

        -- lib is a child of search_lib
        (SELECT distance FROM actor.org_unit_descendants_distance($2) WHERE id = $1),

        -- all others pay cash
        1000
    ) + ((SELECT CASE WHEN addr.latitude IS NULL THEN 0 ELSE -20038 END) + (earth_distance( -- shortest GC distance is returned, only half the circumfrence is needed
            ll_to_earth(
                COALESCE(addr.latitude,plat), -- if the org has no coords, we just
                COALESCE(addr.longitude,plon) -- force 0 distance and let the above tie-break
            ),ll_to_earth(plat,plon)
        ) / 1000)::INT ) -- earth_distance is in meters, convert to kilometers and subtract from largest distance
    FROM actor.org_unit org
		 LEFT JOIN actor.org_address addr ON (org.billing_address = addr.id)
	WHERE org.id = $1;
$$ LANGUAGE SQL STABLE;

-- this version exists mainly to accommodate JSON query transform limitations
-- (the transform argument must be an IDL field, not an entire row/object)
-- XXX is there another way?
CREATE OR REPLACE FUNCTION evergreen.rank_cp(copy_id BIGINT)
RETURNS INTEGER AS $$
DECLARE
    copy asset.copy%ROWTYPE;
BEGIN
    SELECT * INTO copy FROM asset.copy WHERE id = copy_id;
    RETURN evergreen.rank_cp(copy);
END;
$$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.rank_cp(copy asset.copy)
RETURNS INTEGER AS $$
DECLARE
    rank INT;
BEGIN
    WITH totally_available AS (
        SELECT id, 0 AS avail_rank
        FROM config.copy_status
        WHERE opac_visible IS TRUE
            AND copy_active IS TRUE
            AND id != 1 -- "Checked out"
    ), almost_available AS (
        SELECT id, 10 AS avail_rank
        FROM config.copy_status
        WHERE holdable IS TRUE
            AND opac_visible IS TRUE
            AND copy_active IS FALSE
            OR id = 1 -- "Checked out"
    )
    SELECT COALESCE(
        CASE WHEN NOT copy.opac_visible THEN 100 END,
        (SELECT avail_rank FROM totally_available WHERE copy.status IN (id)),
        CASE WHEN copy.holdable THEN
            (SELECT avail_rank FROM almost_available WHERE copy.status IN (id))
        END,
        100
    ) INTO rank;

    RETURN rank;
END;
$$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes(
    bibid BIGINT[], 
    ouid INT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[]
) RETURNS TABLE(id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT) AS $$
    WITH RECURSIVE ou_depth AS (
        SELECT COALESCE(
            $3,
            (
                SELECT depth
                FROM actor.org_unit_type aout
                    INNER JOIN actor.org_unit ou ON ou_type = aout.id
                WHERE ou.id = $2
            )
        ) AS depth
    ), descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ad ON (ad.id = ou.id),
                ou_depth
        WHERE ad.depth = ou_depth.depth
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ), anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
        WHERE ou.id = $2
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ), descendants as (
        SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id)
    )

    SELECT ua.id, ua.name, ua.label_sortkey, MIN(ua.rank) AS rank FROM (
        SELECT acn.id, owning_lib.name, acn.label_sortkey,
            evergreen.rank_cp(acp),
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN descendants AS aou ON (acp.circ_lib = aou.id)
            JOIN actor.org_unit AS owning_lib ON (acn.owning_lib = owning_lib.id)
        WHERE acn.record = ANY ($1)
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
            AND CASE WHEN ('exclude_invisible_acn' = ANY($7)) THEN 
                EXISTS (
                    WITH basevm AS (SELECT c_attrs FROM  asset.patron_default_visibility_mask()),
                         circvm AS (SELECT search.calculate_visibility_attribute_test('circ_lib', ARRAY[acp.circ_lib]) AS mask)
                    SELECT  1 
                      FROM  basevm, circvm, asset.copy_vis_attr_cache acvac
                      WHERE acvac.vis_attr_vector @@ (basevm.c_attrs || '&' || circvm.mask)::query_int
                            AND acvac.target_copy = acp.id
                            AND acvac.record = acn.record
                ) ELSE TRUE END
        GROUP BY acn.id, evergreen.rank_cp(acp), owning_lib.name, acn.label_sortkey, aou.id
        WINDOW w AS (
            ORDER BY 
                COALESCE(
                    CASE WHEN aou.id = $2 THEN -20000 END,
                    CASE WHEN aou.id = $6 THEN -10000 END,
                    (SELECT distance - 5000
                        FROM actor.org_unit_descendants_distance($6) as x
                        WHERE x.id = aou.id AND $6 IN (
                            SELECT q.id FROM actor.org_unit_descendants($2) as q)),
                    (SELECT e.distance FROM actor.org_unit_descendants_distance($2) as e WHERE e.id = aou.id),
                    1000
                ),
                evergreen.rank_cp(acp)
        )
    ) AS ua
    GROUP BY ua.id, ua.name, ua.label_sortkey
    ORDER BY rank, ua.name, ua.label_sortkey
    LIMIT ($4 -> 'acn')::INT
    OFFSET ($5 -> 'acn')::INT;
$$ LANGUAGE SQL STABLE ROWS 10;

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes
    ( bibid BIGINT, ouid INT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, pref_lib INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[] )
    RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT)
    AS $$ SELECT * FROM evergreen.ranked_volumes(ARRAY[$1],$2,$3,$4,$5,$6,$7) $$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION evergreen.located_uris (
    bibid BIGINT[], 
    ouid INT,
    pref_lib INT DEFAULT NULL
) RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank INT) AS $$
    WITH all_orgs AS (SELECT COALESCE( enabled, FALSE ) AS flag FROM config.global_flag WHERE name = 'opac.located_uri.act_as_copy')
    SELECT DISTINCT ON (id) * FROM (
    SELECT acn.id, COALESCE(aou.name,aoud.name), acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           LEFT JOIN actor.org_unit_ancestors( COALESCE($3, $2) ) aou ON (acn.owning_lib = aou.id)
           LEFT JOIN actor.org_unit_descendants( COALESCE($3, $2) ) aoud ON (acn.owning_lib = aoud.id),
           all_orgs
      WHERE acn.record = ANY ($1)
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE
          AND ((NOT all_orgs.flag AND aou.id IS NOT NULL) OR (all_orgs.flag AND COALESCE(aou.id,aoud.id) IS NOT NULL))
    UNION
    SELECT acn.id, COALESCE(aou.name,aoud.name) AS name, acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           LEFT JOIN actor.org_unit_ancestors( $2 ) aou ON (acn.owning_lib = aou.id)
           LEFT JOIN actor.org_unit_descendants( $2 ) aoud ON (acn.owning_lib = aoud.id),
           all_orgs
      WHERE acn.record = ANY ($1)
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE
          AND ((NOT all_orgs.flag AND aou.id IS NOT NULL) OR (all_orgs.flag AND COALESCE(aou.id,aoud.id) IS NOT NULL)))x
    ORDER BY id, pref_ou DESC;
$$
LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.located_uris ( bibid BIGINT, ouid INT, pref_lib INT DEFAULT NULL)
    RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank INT)
    AS $$ SELECT * FROM evergreen.located_uris(ARRAY[$1],$2,$3) $$ LANGUAGE SQL STABLE;

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
CREATE OR REPLACE FUNCTION unapi.aou    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acnp   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acns   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acn    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.ssub   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sdist  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sstr   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sitem  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sunit  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sisum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sbsum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sssum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.siss   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.auri   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acp    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acpn   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acl    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.ccs    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.bre (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.mmr (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.bmp    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.mra    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.mmr_mra    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, pref_lib INT DEFAULT NULL) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.circ   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT DEFAULT '-', depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (
    bid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.mmr_holdings_xml (
    mid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL, pref_lib INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.metabib_virtual_record_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL, pref_lib INT DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.memoize (classname TEXT, obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL, pref_lib INT DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    layout          unapi.bre_output_layout%ROWTYPE;
    transform       config.xml_transform%ROWTYPE;
    item_format     TEXT;
    tmp_xml         TEXT;
    xmlns_uri       TEXT := 'http://open-ils.org/spec/feed-xml/v1';
    ouid            INT;
    element_list    TEXT[];
BEGIN

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;
    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO transform FROM config.xml_transform WHERE name = layout.transform;
    xmlns_uri := COALESCE(transform.namespace_uri,xmlns_uri);

    -- Gather the bib xml
    SELECT XMLAGG( unapi.bre(i, format, '', includes, org, depth, slimit, soffset, include_xmlns, pref_lib)) INTO tmp_xml FROM UNNEST( id_list ) i;

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
$F$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION unapi.metabib_virtual_record_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL, pref_lib INT DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    layout          unapi.bre_output_layout%ROWTYPE;
    transform       config.xml_transform%ROWTYPE;
    item_format     TEXT;
    tmp_xml         TEXT;
    xmlns_uri       TEXT := 'http://open-ils.org/spec/feed-xml/v1';
    ouid            INT;
    element_list    TEXT[];
BEGIN

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;
    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO transform FROM config.xml_transform WHERE name = layout.transform;
    xmlns_uri := COALESCE(transform.namespace_uri,xmlns_uri);

    -- Gather the bib xml
    SELECT XMLAGG( unapi.mmr(i, format, '', includes, org, depth, slimit, soffset, include_xmlns, pref_lib)) INTO tmp_xml FROM UNNEST( id_list ) i;

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
$F$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION unapi.bre (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$
DECLARE
    me      biblio.record_entry%ROWTYPE;
    layout  unapi.bre_output_layout%ROWTYPE;
    xfrm    config.xml_transform%ROWTYPE;
    ouid    INT;
    tmp_xml TEXT;
    top_el  TEXT;
    output  XML;
    hxml    XML;
    axml    XML;
    source  XML;
BEGIN

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

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

    -- grab bib_source, if any
    IF ('cbs' = ANY (includes) AND me.source IS NOT NULL) THEN
        source := unapi.cbs(me.source,NULL,NULL,NULL,NULL);
    ELSE
        source := NULL::XML;
    END IF;

    -- grab SVF if we need them
    IF ('mra' = ANY (includes)) THEN 
        axml := unapi.mra(obj_id,NULL,NULL,NULL,NULL);
    ELSE
        axml := NULL::XML;
    END IF;

    -- grab holdings if we need them
    IF ('holdings_xml' = ANY (includes)) THEN 
        hxml := unapi.holdings_xml(obj_id, ouid, org, depth, array_remove(includes,'holdings_xml'), slimit, soffset, include_xmlns, pref_lib);
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

    IF source IS NOT NULL THEN
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', source || '</' || top_el || E'>\\1');
    END IF;

    IF axml IS NOT NULL THEN 
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', axml || '</' || top_el || E'>\\1');
    END IF;

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

    IF ('bre.extern' = ANY (includes)) THEN 
        output := REGEXP_REPLACE(
            tmp_xml,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name extern,
                XMLATTRIBUTES(
                    'http://open-ils.org/spec/biblio/v1' AS xmlns,
                    me.creator AS creator,
                    me.editor AS editor,
                    me.create_date AS create_date,
                    me.edit_date AS edit_date,
                    me.quality AS quality,
                    me.fingerprint AS fingerprint,
                    me.tcn_source AS tcn_source,
                    me.tcn_value AS tcn_value,
                    me.owner AS owner,
                    me.share_depth AS share_depth,
                    me.active AS active,
                    me.deleted AS deleted
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := tmp_xml;
    END IF;

    output := REGEXP_REPLACE(output::TEXT,E'>\\s+<','><','gs')::XML;
    RETURN output;
END;
$F$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (
    bid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('bre' = ANY ($5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id,
                    (SELECT record_has_holdable_copy FROM asset.record_has_holdable_copy($1)) AS has_holdable
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
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('pref_lib' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($9,  $1)
                                     ORDER BY 1
                     )x)
                 ),
                 CASE 
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT(
                            name monograph_parts,
                            (SELECT XMLAGG(bmp) FROM (
                                SELECT  unapi.bmp( id, 'xml', 'monograph_part', array_remove( array_remove($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE)
                                  FROM  biblio.monograph_part
                                  WHERE NOT deleted AND record = $1
                            )x)
                        )
                     ELSE NULL
                 END,
                 XMLELEMENT(
                     name volumes,
                     (SELECT XMLAGG(acn ORDER BY rank, name, label_sortkey) FROM (
                        -- Physical copies
                        SELECT  unapi.acn(y.id,'xml','volume',array_remove( array_remove($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), y.rank, name, label_sortkey
                        FROM evergreen.ranked_volumes($1, $2, $4, $6, $7, $9, $5) AS y
                        UNION ALL
                        -- Located URIs
                        SELECT unapi.acn(uris.id,'xml','volume',array_remove( array_remove($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), uris.rank, name, label_sortkey
                        FROM evergreen.located_uris($1, $2, $9) AS uris
                     )x)
                 ),
                 CASE WHEN ('ssub' = ANY ($5)) THEN 
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry = $1
                        )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('acp' = ANY ($5)) THEN 
                     XMLELEMENT(
                         name foreign_copies,
                         (SELECT XMLAGG(acp) FROM (
                            SELECT  unapi.acp(p.target_copy,'xml','copy',array_remove($5,'acp'), $3, $4, $6, $7, FALSE)
                              FROM  biblio.peer_bib_copy_map p
                                    JOIN asset.copy c ON (p.target_copy = c.id)
                              WHERE NOT c.deleted AND p.peer_record = $1
                            LIMIT ($6 -> 'acp')::INT
                            OFFSET ($7 -> 'acp')::INT
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.ssub ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name subscription,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@ssub/' || id AS id,
                        'tag:open-ils.org:U2@aou/' || owning_lib AS owning_lib,
                        start_date AS start, end_date AS end, expected_date_offset
                    ),
                    CASE 
                        WHEN ('sdist' = ANY ($4)) THEN
                            XMLELEMENT( name distributions,
                                (SELECT XMLAGG(sdist) FROM (
                                    SELECT  unapi.sdist( id, 'xml', 'distribution', array_remove($4,'ssub'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.distribution
                                      WHERE subscription = ssub.id
                                )x)
                            )
                        ELSE NULL
                    END
                )
          FROM  serial.subscription ssub
          WHERE id = $1
          GROUP BY id, start_date, end_date, expected_date_offset, owning_lib;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sdist ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name distribution,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@sdist/' || id AS id,
            			'tag:open-ils.org:U2@acn/' || receive_call_number AS receive_call_number,
			            'tag:open-ils.org:U2@acn/' || bind_call_number AS bind_call_number,
                        unit_label_prefix, label, unit_label_suffix, summary_method
                    ),
                    unapi.aou( holding_lib, $2, 'holding_lib', array_remove($4,'sdist'), $5, $6, $7, $8),
                    CASE WHEN subscription IS NOT NULL AND ('ssub' = ANY ($4)) THEN unapi.ssub( subscription, 'xml', 'subscription', array_remove($4,'sdist'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE 
                        WHEN ('sstr' = ANY ($4)) THEN
                            XMLELEMENT( name streams,
                                (SELECT XMLAGG(sstr) FROM (
                                    SELECT  unapi.sstr( id, 'xml', 'stream', array_remove($4,'sdist'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.stream
                                      WHERE distribution = sdist.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    XMLELEMENT( name summaries,
                        CASE 
                            WHEN ('sbsum' = ANY ($4)) THEN
                                (SELECT XMLAGG(sbsum) FROM (
                                    SELECT  unapi.sbsum( id, 'xml', 'serial_summary', array_remove($4,'sdist'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.basic_summary
                                      WHERE distribution = sdist.id
                                )x)
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('sisum' = ANY ($4)) THEN
                                (SELECT XMLAGG(sisum) FROM (
                                    SELECT  unapi.sisum( id, 'xml', 'serial_summary', array_remove($4,'sdist'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.index_summary
                                      WHERE distribution = sdist.id
                                )x)
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('sssum' = ANY ($4)) THEN
                                (SELECT XMLAGG(sssum) FROM (
                                    SELECT  unapi.sssum( id, 'xml', 'serial_summary', array_remove($4,'sdist'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.supplement_summary
                                      WHERE distribution = sdist.id
                                )x)
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.distribution sdist
          WHERE id = $1
          GROUP BY id, label, unit_label_prefix, unit_label_suffix, holding_lib, summary_method, subscription, receive_call_number, bind_call_number;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sstr ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name stream,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sstr/' || id AS id,
                    routing_label
                ),
                CASE WHEN distribution IS NOT NULL AND ('sdist' = ANY ($4)) THEN unapi.sssum( distribution, 'xml', 'distribtion', array_remove($4,'sstr'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                CASE 
                    WHEN ('sitem' = ANY ($4)) THEN
                        XMLELEMENT( name items,
                            (SELECT XMLAGG(sitem) FROM (
                                SELECT  unapi.sitem( id, 'xml', 'serial_item', array_remove($4,'sstr'), $5, $6, $7, $8, FALSE)
                                  FROM  serial.item
                                  WHERE stream = sstr.id
                            )x)
                        )
                    ELSE NULL
                END
            )
      FROM  serial.stream sstr
      WHERE id = $1
      GROUP BY id, routing_label, distribution;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.siss ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name issuance,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@siss/' || id AS id,
                    create_date, edit_date, label, date_published,
                    holding_code, holding_type, holding_link_id
                ),
                CASE WHEN subscription IS NOT NULL AND ('ssub' = ANY ($4)) THEN unapi.ssub( subscription, 'xml', 'subscription', array_remove($4,'siss'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                CASE 
                    WHEN ('sitem' = ANY ($4)) THEN
                        XMLELEMENT( name items,
                            (SELECT XMLAGG(sitem) FROM (
                                SELECT  unapi.sitem( id, 'xml', 'serial_item', array_remove($4,'siss'), $5, $6, $7, $8, FALSE)
                                  FROM  serial.item
                                  WHERE issuance = sstr.id
                            )x)
                        )
                    ELSE NULL
                END
            )
      FROM  serial.issuance sstr
      WHERE id = $1
      GROUP BY id, create_date, edit_date, label, date_published, holding_code, holding_type, holding_link_id, subscription;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sitem ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_item,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@sitem/' || id AS id,
                        'tag:open-ils.org:U2@siss/' || issuance AS issuance,
                        date_expected, date_received
                    ),
                    CASE WHEN issuance IS NOT NULL AND ('siss' = ANY ($4)) THEN unapi.siss( issuance, $2, 'issuance', array_remove($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN stream IS NOT NULL AND ('sstr' = ANY ($4)) THEN unapi.sstr( stream, $2, 'stream', array_remove($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN unit IS NOT NULL AND ('sunit' = ANY ($4)) THEN unapi.sunit( unit, $2, 'serial_unit', array_remove($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN uri IS NOT NULL AND ('auri' = ANY ($4)) THEN unapi.auri( uri, $2, 'uri', array_remove($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END
--                    XMLELEMENT( name notes,
--                        CASE 
--                            WHEN ('acpn' = ANY ($4)) THEN
--                                (SELECT XMLAGG(acpn) FROM (
--                                    SELECT  unapi.acpn( id, 'xml', 'copy_note', array_remove($4,'acp'), $5, $6, $7, $8)
--                                      FROM  asset.copy_note
--                                      WHERE owning_copy = cp.id AND pub
--                                )x)
--                            ELSE NULL
--                        END
--                    )
                )
          FROM  serial.item sitem
          WHERE id = $1;
$F$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION unapi.sssum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sssum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', array_remove($4,'ssum'), $5, $6, $7, $8, FALSE) ELSE NULL END
            )
      FROM  serial.supplement_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sbsum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sbsum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', array_remove($4,'ssum'), $5, $6, $7, $8, FALSE) ELSE NULL END
            )
      FROM  serial.basic_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sisum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sisum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', array_remove($4,'ssum'), $5, $6, $7, $8, FALSE) ELSE NULL END
            )
      FROM  serial.index_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION unapi.aou ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acl ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name location,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident,
                    holdable,
                    opac_visible,
                    label_prefix AS prefix,
                    label_suffix AS suffix
                ),
                name
            )
      FROM  asset.copy_location
      WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.ccs ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name status,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident,
                    holdable,
                    opac_visible
                ),
                name
            )
      FROM  config.copy_status
      WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acpn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acpt ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy_tag,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        copy_tag_type.label AS type
                    ),
                    copy_tag.value
                )
          FROM  asset.copy_tag
          JOIN  config.copy_tag_type
          ON    copy_tag_type.code = copy_tag.tag_type
          WHERE copy_tag.id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.bmp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
                                    SELECT  unapi.acp( cp.id, 'xml', 'copy', array_remove($4,'bmp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy cp
                                            JOIN asset.copy_part_map cpm ON (cpm.target_copy = cp.id)
                                      WHERE cpm.part = $1
                                          AND cp.deleted IS FALSE
                                      ORDER BY COALESCE(cp.copy_number,0), cp.barcode
                                      LIMIT ($7 -> 'acp')::INT
                                      OFFSET ($8 -> 'acp')::INT

                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( record, 'marcxml', 'record', array_remove($4,'bmp'), $5, $6, $7, $8, FALSE) ELSE NULL END
                )
          FROM  biblio.monograph_part
          WHERE NOT deleted AND id = $1
          GROUP BY id, label, label_sortkey, record;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id, id AS copy_id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible, age_protect
                    ),
                    unapi.ccs( status, $2, 'status', array_remove($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', array_remove($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', array_remove($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', array_remove($4,'acp'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', array_remove($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE 
                        WHEN ('acpn' = ANY ($4)) THEN
                            XMLELEMENT( name copy_notes,
                                (SELECT XMLAGG(acpn) FROM (
                                    SELECT  unapi.acpn( id, 'xml', 'copy_note', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_note
                                      WHERE owning_copy = cp.id AND pub
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE
                        WHEN ('acpt' = ANY ($4)) THEN
                            XMLELEMENT( name copy_tags,
                                (SELECT XMLAGG(acpt) FROM (
                                    SELECT  unapi.acpt( copy_tag.id, 'xml', 'copy_tag', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_tag_copy_map
                                      JOIN asset.copy_tag ON copy_tag.id = copy_tag_copy_map.tag
                                      WHERE copy_tag_copy_map.copy = cp.id AND copy_tag.pub
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE 
                        WHEN ('ascecm' = ANY ($4)) THEN
                            XMLELEMENT( name statcats,
                                (SELECT XMLAGG(ascecm) FROM (
                                    SELECT  unapi.ascecm( stat_cat_entry, 'xml', 'statcat', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.stat_cat_entry_copy_map
                                      WHERE owning_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE
                        WHEN ('bre' = ANY ($4)) THEN
                            XMLELEMENT( name foreign_records,
                                (SELECT XMLAGG(bre) FROM (
                                    SELECT  unapi.bre(peer_record,'marcxml','record','{}'::TEXT[], $5, $6, $7, $8, FALSE)
                                      FROM  biblio.peer_bib_copy_map
                                      WHERE target_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE 
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                (SELECT XMLAGG(bmp) FROM (
                                    SELECT  unapi.bmp( part, 'xml', 'monograph_part', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_part_map
                                      WHERE target_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE 
                        WHEN ('circ' = ANY ($4)) THEN
                            XMLELEMENT( name current_circulation,
                                (SELECT XMLAGG(circ) FROM (
                                    SELECT  unapi.circ( id, 'xml', 'circ', array_remove($4,'circ'), $5, $6, $7, $8, FALSE)
                                      FROM  action.circulation
                                      WHERE target_copy = cp.id
                                            AND checkin_time IS NULL
                                )x)
                            )
                        ELSE NULL
                    END
                )
          FROM  asset.copy cp
          WHERE id = $1
              AND cp.deleted IS FALSE
          GROUP BY id, status, location, circ_lib, call_number, create_date,
              edit_date, copy_number, circulate, deposit, ref, holdable,
              deleted, deposit_amount, price, barcode, circ_modifier,
              circ_as_type, opac_visible, age_protect;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sunit ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_unit,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id, id AS copy_id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible, age_protect,
                        status_changed_time, floating, mint_condition,
                        detailed_contents, sort_key, summary_contents, cost 
                    ),
                    unapi.ccs( status, $2, 'status', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', array_remove($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE 
                            WHEN ('acpn' = ANY ($4)) THEN
                                (SELECT XMLAGG(acpn) FROM (
                                    SELECT  unapi.acpn( id, 'xml', 'copy_note', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_note
                                      WHERE owning_copy = cp.id AND pub
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name copy_tags,
                        CASE
                            WHEN ('acpt' = ANY ($4)) THEN
                                (SELECT XMLAGG(acpt) FROM (
                                    SELECT  unapi.acpt( copy_tag.id, 'xml', 'copy_tag', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_tag_copy_map
                                      JOIN  asset.copy_tag ON copy_tag.id = copy_tag_copy_map.tag
                                      WHERE copy_tag_copy_map.copy = cp.id AND copy_tag.pub
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE 
                            WHEN ('ascecm' = ANY ($4)) THEN
                                (SELECT XMLAGG(ascecm) FROM (
                                    SELECT  unapi.ascecm( stat_cat_entry, 'xml', 'statcat', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.stat_cat_entry_copy_map
                                      WHERE owning_copy = cp.id
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name foreign_records,
                        CASE
                            WHEN ('bre' = ANY ($4)) THEN
                                (SELECT XMLAGG(bre) FROM (
                                    SELECT  unapi.bre(peer_record,'marcxml','record','{}'::TEXT[], $5, $6, $7, $8, FALSE)
                                      FROM  biblio.peer_bib_copy_map
                                      WHERE target_copy = cp.id
                                )x)
                            ELSE NULL
                        END
                    ),
                    CASE 
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                (SELECT XMLAGG(bmp) FROM (
                                    SELECT  unapi.bmp( part, 'xml', 'monograph_part', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_part_map
                                      WHERE target_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE 
                        WHEN ('circ' = ANY ($4)) THEN
                            XMLELEMENT( name current_circulation,
                                (SELECT XMLAGG(circ) FROM (
                                    SELECT  unapi.circ( id, 'xml', 'circ', array_remove($4,'circ'), $5, $6, $7, $8, FALSE)
                                      FROM  action.circulation
                                      WHERE target_copy = cp.id
                                            AND checkin_time IS NULL
                                )x)
                            )
                        ELSE NULL
                    END
                )
          FROM  serial.unit cp
          WHERE id = $1
              AND cp.deleted IS FALSE
          GROUP BY id, status, location, circ_lib, call_number, create_date,
              edit_date, copy_number, circulate, floating, mint_condition,
              deposit, ref, holdable, deleted, deposit_amount, price,
              barcode, circ_modifier, circ_as_type, opac_visible,
              status_changed_time, detailed_contents, sort_key,
              summary_contents, cost, age_protect;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acn/' || acn.id AS id,
                        acn.id AS vol_id, o.shortname AS lib,
                        o.opac_visible AS opac_visible,
                        deleted, label, label_sortkey, label_class, record
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', array_remove($4,'acn'), $5, $6, $7, $8),
                    CASE 
                        WHEN ('acp' = ANY ($4)) THEN
                            CASE WHEN $6 IS NOT NULL THEN
                                XMLELEMENT( name copies,
                                    (SELECT XMLAGG(acp ORDER BY rank_avail) FROM (
                                        SELECT  unapi.acp( cp.id, 'xml', 'copy', array_remove($4,'acn'), $5, $6, $7, $8, FALSE),
                                            evergreen.rank_cp(cp) AS rank_avail
                                          FROM  asset.copy cp
                                                JOIN actor.org_unit_descendants( (SELECT id FROM actor.org_unit WHERE shortname = $5), $6) aoud ON (cp.circ_lib = aoud.id)
                                          WHERE cp.call_number = acn.id
                                              AND cp.deleted IS FALSE
                                          ORDER BY rank_avail, COALESCE(cp.copy_number,0), cp.barcode
                                          LIMIT ($7 -> 'acp')::INT
                                          OFFSET ($8 -> 'acp')::INT
                                    )x)
                                )
                            ELSE
                                XMLELEMENT( name copies,
                                    (SELECT XMLAGG(acp ORDER BY rank_avail) FROM (
                                        SELECT  unapi.acp( cp.id, 'xml', 'copy', array_remove($4,'acn'), $5, $6, $7, $8, FALSE),
                                            evergreen.rank_cp(cp) AS rank_avail
                                          FROM  asset.copy cp
                                                JOIN actor.org_unit_descendants( (SELECT id FROM actor.org_unit WHERE shortname = $5) ) aoud ON (cp.circ_lib = aoud.id)
                                          WHERE cp.call_number = acn.id
                                              AND cp.deleted IS FALSE
                                          ORDER BY rank_avail, COALESCE(cp.copy_number,0), cp.barcode
                                          LIMIT ($7 -> 'acp')::INT
                                          OFFSET ($8 -> 'acp')::INT
                                    )x)
                                )
                            END
                        ELSE NULL
                    END,
                    XMLELEMENT(
                        name uris,
                        (SELECT XMLAGG(auri) FROM (SELECT unapi.auri(uri,'xml','uri', array_remove($4,'acn'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE call_number = acn.id)x)
                    ),
                    unapi.acnp( acn.prefix, 'marcxml', 'prefix', array_remove($4,'acn'), $5, $6, $7, $8, FALSE),
                    unapi.acns( acn.suffix, 'marcxml', 'suffix', array_remove($4,'acn'), $5, $6, $7, $8, FALSE),
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( acn.record, 'marcxml', 'record', array_remove($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END
                ) AS x
          FROM  asset.call_number acn
                JOIN actor.org_unit o ON (o.id = acn.owning_lib)
          WHERE acn.id = $1
              AND acn.deleted IS FALSE
          GROUP BY acn.id, o.shortname, o.opac_visible, deleted, label, label_sortkey, label_class, owning_lib, record, acn.prefix, acn.suffix;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acnp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_prefix,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        id AS ident,
                        label,
                        'tag:open-ils.org:U2@aou/' || owning_lib AS owning_lib,
                        label_sortkey
                    )
                )
          FROM  asset.call_number_prefix
          WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acns ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_suffix,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        id AS ident,
                        label,
                        'tag:open-ils.org:U2@aou/' || owning_lib AS owning_lib,
                        label_sortkey
                    )
                )
          FROM  asset.call_number_suffix
          WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.auri ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name uri,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@auri/' || uri.id AS id,
                        use_restriction,
                        href,
                        label
                    ),
                    CASE 
                        WHEN ('acn' = ANY ($4)) THEN
                            XMLELEMENT( name copies,
                                (SELECT XMLAGG(acn) FROM (SELECT unapi.acn( call_number, 'xml', 'copy', array_remove($4,'auri'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE uri = uri.id)x)
                            )
                        ELSE NULL
                    END
                ) AS x
          FROM  asset.uri uri
          WHERE uri.id = $1
          GROUP BY uri.id, use_restriction, href, label;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.cbs ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name bib_source,
                XMLATTRIBUTES(
                    NULL AS xmlns, -- TODO needs equivalent to http://open-ils.org/spec/holdings/v1
                    id AS ident,
                    quality,
                    transcendant,
                    can_have_copies
                ),
                source
            )
      FROM  config.bib_source
      WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.mra (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE
) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
        name attributes,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@mra/' || $1 AS id, 
            'tag:open-ils.org:U2@bre/' || $1 AS record 
        ),  
        (SELECT XMLAGG(foo.y)
          FROM (
            SELECT  XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            mra.attr AS name,
                            cvm.value AS "coded-value",
                            cvm.id AS "cvmid",
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        mra.value
                    )
              FROM  metabib.record_attr_flat mra
                    JOIN config.record_attr_definition rad ON (mra.attr = rad.name)
                    LEFT JOIN config.coded_value_map cvm ON (cvm.ctype = mra.attr AND code = mra.value)
              WHERE mra.id = $1
            )foo(y)
        )   
    )   
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.circ (obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT DEFAULT '-', depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT XMLELEMENT(
        name circ,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@circ/' || id AS id,
            xact_start,
            due_date
        ),
        CASE WHEN ('aou' = ANY ($4)) THEN unapi.aou( circ_lib, $2, 'circ_lib', array_remove($4,'circ'), $5, $6, $7, $8, FALSE) ELSE NULL END,
        CASE WHEN ('acp' = ANY ($4)) THEN unapi.acp( circ_lib, $2, 'target_copy', array_remove($4,'circ'), $5, $6, $7, $8, FALSE) ELSE NULL END
    )
    FROM action.circulation
    WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.mmr_mra (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
        name attributes,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@mmr/' || $1 AS metarecord
        ),
        (SELECT XMLAGG(foo.y)
          FROM (
            WITH sourcelist AS (
                WITH aou AS (SELECT COALESCE(id, (evergreen.org_top()).id) AS id FROM actor.org_unit WHERE shortname = $5 LIMIT 1),
                     basevm AS (SELECT c_attrs FROM  asset.patron_default_visibility_mask()),
                     circvm AS (SELECT search.calculate_visibility_attribute_test('circ_lib', ARRAY_AGG(aoud.id)) AS mask
                                  FROM aou, LATERAL actor.org_unit_descendants(aou.id, $6) aoud)
                SELECT  source
                  FROM  aou, circvm, basevm, metabib.metarecord_source_map mmsm
                  WHERE mmsm.metarecord = $1 AND (
                    EXISTS (
                        SELECT  1
                          FROM  circvm, basevm, asset.copy_vis_attr_cache acvac
                          WHERE acvac.vis_attr_vector @@ (basevm.c_attrs || '&' || circvm.mask)::query_int
                                AND acvac.record = mmsm.source
                    )
                    OR EXISTS (SELECT 1 FROM evergreen.located_uris(source, aou.id, $10) LIMIT 1)
                    OR EXISTS (SELECT 1 FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = mmsm.source)
                )
            )
            SELECT  cmra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            cmra.attr AS name,
                            cmra.value AS "coded-value",
                            cmra.aid AS "cvmid",
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter,
                            cmra.source_list
                        ),
                        cmra.value
                    )
              FROM  (
                SELECT DISTINCT aid, attr, value, STRING_AGG(x.id::TEXT, ',') AS source_list
                  FROM (
                    SELECT  v.source AS id,
                            c.id AS aid,
                            c.ctype AS attr,
                            c.code AS value
                      FROM  metabib.record_attr_vector_list v
                            JOIN config.coded_value_map c ON ( c.id = ANY( v.vlist ) )
                    ) AS x
                    JOIN sourcelist ON (x.id = sourcelist.source)
                    GROUP BY 1, 2, 3
                ) AS cmra
                JOIN config.record_attr_definition rad ON (cmra.attr = rad.name)
                UNION ALL
            SELECT  umra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            umra.attr AS name,
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        umra.value
                    )
              FROM  (
                SELECT DISTINCT aid, attr, value
                  FROM (
                    SELECT  v.source AS id,
                            m.id AS aid,
                            m.attr AS attr,
                            m.value AS value
                      FROM  metabib.record_attr_vector_list v
                            JOIN metabib.uncontrolled_record_attr_value m ON ( m.id = ANY( v.vlist ) )
                    ) AS x
                    JOIN sourcelist ON (x.id = sourcelist.source)
                ) AS umra
                JOIN config.record_attr_definition rad ON (umra.attr = rad.name)
                ORDER BY 1

            )foo(id,y)
        )
    )
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.mmr_holdings_xml (
    mid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('mmr' = ANY ($5)) THEN 'tag:open-ils.org:U2@mmr/' || $1 || '/' || $3 ELSE NULL END AS id,
                    (SELECT metarecord_has_holdable_copy FROM asset.metarecord_has_holdable_copy($1)) AS has_holdable
                 ),
                 XMLELEMENT(
                     name counts,
                     (SELECT  XMLAGG(XMLELEMENT::XML) FROM (
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_metarecord_copy_count($2,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_ou_metarecord_copy_count($2, $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('pref_lib' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_metarecord_copy_count($9,  $1)
                                     ORDER BY 1
                     )x)
                 ),
                 -- XXX monograph_parts and foreign_copies are skipped in MRs ... put them back some day?
                 XMLELEMENT(
                     name volumes,
                     (SELECT XMLAGG(acn ORDER BY rank, name, label_sortkey) FROM (
                        -- Physical copies
                        SELECT  unapi.acn(y.id,'xml','volume',array_remove( array_remove($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), y.rank, name, label_sortkey
                        FROM evergreen.ranked_volumes((SELECT ARRAY_AGG(source) FROM metabib.metarecord_source_map WHERE metarecord = $1), $2, $4, $6, $7, $9, $5) AS y
                        UNION ALL
                        -- Located URIs
                        SELECT unapi.acn(uris.id,'xml','volume',array_remove( array_remove($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), uris.rank, name, label_sortkey
                        FROM evergreen.located_uris((SELECT ARRAY_AGG(source) FROM metabib.metarecord_source_map WHERE metarecord = $1), $2, $9) AS uris
                     )x)
                 ),
                 CASE WHEN ('ssub' = ANY ($5)) THEN
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry IN (SELECT source FROM metabib.metarecord_source_map WHERE metarecord = $1)
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.mmr (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$
DECLARE
    mmrec   metabib.metarecord%ROWTYPE;
    leadrec biblio.record_entry%ROWTYPE;
    subrec biblio.record_entry%ROWTYPE;
    layout  unapi.bre_output_layout%ROWTYPE;
    xfrm    config.xml_transform%ROWTYPE;
    ouid    INT;
    xml_buf TEXT; -- growing XML document
    tmp_xml TEXT; -- single-use XML string
    xml_frag TEXT; -- single-use XML fragment
    top_el  TEXT;
    output  XML;
    hxml    XML;
    axml    XML;
    subxml  XML; -- subordinate records elements
    sub_xpath TEXT; 
    parts   TEXT[]; 
BEGIN

    -- xpath for extracting bre.marc values from subordinate records 
    -- so they may be appended to the MARC of the master record prior
    -- to XSLT processing.
    -- subjects, isbn, issn, upc -- anything else?
    sub_xpath := 
      '//*[starts-with(@tag, "6") or @tag="020" or @tag="022" or @tag="024"]';

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;

    IF ouid IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT INTO mmrec * FROM metabib.metarecord WHERE id = obj_id;
    IF NOT FOUND THEN
        RETURN NULL::XML;
    END IF;

    -- TODO: aggregate holdings from constituent records
    IF format = 'holdings_xml' THEN -- the special case
        output := unapi.mmr_holdings_xml(
            obj_id, ouid, org, depth,
            array_remove(includes,'holdings_xml'),
            slimit, soffset, include_xmlns, pref_lib);
        RETURN output;
    END IF;

    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO xfrm FROM config.xml_transform WHERE name = layout.transform;

    SELECT INTO leadrec * FROM biblio.record_entry WHERE id = mmrec.master_record;

    -- Grab distinct MVF for all records if requested
    IF ('mra' = ANY (includes)) THEN 
        axml := unapi.mmr_mra(obj_id,NULL,NULL,NULL,org,depth,NULL,NULL,TRUE,pref_lib);
    ELSE
        axml := NULL::XML;
    END IF;

    xml_buf = leadrec.marc;

    hxml := NULL::XML;
    IF ('holdings_xml' = ANY (includes)) THEN
        hxml := unapi.mmr_holdings_xml(
                    obj_id, ouid, org, depth,
                    array_remove(includes,'holdings_xml'),
                    slimit, soffset, include_xmlns, pref_lib);
    END IF;

    subxml := NULL::XML;
    parts := '{}'::TEXT[];
    FOR subrec IN SELECT bre.* FROM biblio.record_entry bre
         JOIN metabib.metarecord_source_map mmsm ON (mmsm.source = bre.id)
         JOIN metabib.metarecord mmr ON (mmr.id = mmsm.metarecord)
         WHERE mmr.id = obj_id AND NOT bre.deleted
         ORDER BY CASE WHEN bre.id = mmr.master_record THEN 0 ELSE bre.id END
         LIMIT COALESCE((slimit->'bre')::INT, 5) LOOP

        IF subrec.id = leadrec.id THEN CONTINUE; END IF;
        -- Append choice data from the the non-lead records to the 
        -- the lead record document

        parts := parts || xpath(sub_xpath, subrec.marc::XML)::TEXT[];
    END LOOP;

    SELECT STRING_AGG( DISTINCT p , '' )::XML INTO subxml FROM UNNEST(parts) p;

    -- append data from the subordinate records to the 
    -- main record document before applying the XSLT

    IF subxml IS NOT NULL THEN 
        xml_buf := REGEXP_REPLACE(xml_buf, 
            '</record>(.*?)$', subxml || '</record>' || E'\\1');
    END IF;

    IF format = 'marcxml' THEN
         -- If we're not using the prefixed namespace in 
         -- this record, then remove all declarations of it
        IF xml_buf !~ E'<marc:' THEN
           xml_buf := REGEXP_REPLACE(xml_buf, 
            ' xmlns:marc="http://www.loc.gov/MARC21/slim"', '', 'g');
        END IF; 
    ELSE
        xml_buf := oils_xslt_process(xml_buf, xfrm.xslt)::XML;
    END IF;

    -- update top_el to reflect the change in xml_buf, which may
    -- now be a different type of document (e.g. record -> mods)
    top_el := REGEXP_REPLACE(xml_buf, E'^.*?<((?:\\S+:)?' || 
        layout.holdings_element || ').*$', E'\\1');

    IF axml IS NOT NULL THEN 
        xml_buf := REGEXP_REPLACE(xml_buf, 
            '</' || top_el || '>(.*?)$', axml || '</' || top_el || E'>\\1');
    END IF;

    IF hxml IS NOT NULL THEN
        xml_buf := REGEXP_REPLACE(xml_buf, 
            '</' || top_el || '>(.*?)$', hxml || '</' || top_el || E'>\\1');
    END IF;

    IF ('mmr.unapi' = ANY (includes)) THEN 
        output := REGEXP_REPLACE(
            xml_buf,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name abbr,
                XMLATTRIBUTES(
                    'http://www.w3.org/1999/xhtml' AS xmlns,
                    'unapi-id' AS class,
                    'tag:open-ils.org:U2@mmr/' || obj_id || '/' || org AS title
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := xml_buf;
    END IF;

    -- remove ignorable whitesace
    output := REGEXP_REPLACE(output::TEXT,E'>\\s+<','><','gs')::XML;
    RETURN output;
END;
$F$ LANGUAGE PLPGSQL STABLE;

-- note not adding a companion version which takes an int[] as 
-- the first arument, similar to evergreen.located_uris(), because
-- json_query is unable to distinguish between the type of paramaters, 
-- leading to 'Could not choose a best candidate function' errors.
CREATE OR REPLACE FUNCTION evergreen.located_uris_as_uris 
    (bibid BIGINT, ouid INT, pref_lib INT DEFAULT NULL)
    RETURNS SETOF asset.uri AS $FUNK$
    /* Maps a bib directly to its scoped asset.uri's */

    SELECT uri.* 
    FROM evergreen.located_uris($1, $2, $3) located_uri
    JOIN asset.uri_call_number_map map ON (map.call_number = located_uri.id)
    JOIN asset.uri uri ON (uri.id = map.uri)
$FUNK$ LANGUAGE SQL STABLE;


/*

 -- Some test queries

SELECT unapi.memoize( 'bre', 1,'mods32','','{holdings_xml,acp}'::TEXT[], 'SYS1');
SELECT unapi.memoize( 'bre', 1,'marcxml','','{holdings_xml,acp}'::TEXT[], 'SYS1');
SELECT unapi.memoize( 'bre', 1,'holdings_xml','','{holdings_xml,acp}'::TEXT[], 'SYS1');

SELECT unapi.biblio_record_entry_feed('{1}'::BIGINT[],'mods32','{holdings_xml,acp}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://c64/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');

SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'marcxml','{}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');
EXPLAIN ANALYZE SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'marcxml','{}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');
EXPLAIN ANALYZE SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'marcxml','{holdings_xml}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');
EXPLAIN ANALYZE SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'mods32','{holdings_xml}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');

SELECT unapi.biblio_record_entry_feed('{216}'::BIGINT[],'marcxml','{}'::TEXT[], 'BR1');
EXPLAIN ANALYZE SELECT unapi.bre(216,'marcxml','record','{holdings_xml,bre.unapi}'::TEXT[], 'BR1');
EXPLAIN ANALYZE SELECT unapi.bre(216,'holdings_xml','record','{}'::TEXT[], 'BR1');
EXPLAIN ANALYZE SELECT unapi.holdings_xml(216,4,'BR1',2,'{bre}'::TEXT[]);
EXPLAIN ANALYZE SELECT unapi.bre(216,'mods32','record','{}'::TEXT[], 'BR1');

-- Limit to 5 call numbers, 5 copies, with a preferred library of 4 (BR1), in SYS2 at a depth of 0
EXPLAIN ANALYZE SELECT unapi.bre(36,'marcxml','record','{holdings_xml,mra,acp,acnp,acns,bmp}','SYS2',0,'acn=>5,acp=>5',NULL,TRUE,4);

*/

COMMIT;

