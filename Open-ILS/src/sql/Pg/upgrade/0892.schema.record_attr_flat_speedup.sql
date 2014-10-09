BEGIN;

SELECT evergreen.upgrade_deps_block_check('0892', :eg_version);

CREATE OR REPLACE VIEW metabib.record_attr_flat AS
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
                WITH aou AS (SELECT COALESCE(id, (evergreen.org_top()).id) AS id
                    FROM actor.org_unit WHERE shortname = $5 LIMIT 1)
                SELECT source
                FROM metabib.metarecord_source_map, aou
                WHERE metarecord = $1 AND (
                    EXISTS (
                        SELECT 1 FROM asset.opac_visible_copies
                        WHERE record = source AND circ_lib IN (
                            SELECT id FROM actor.org_unit_descendants(aou.id, $6))
                        LIMIT 1
                    )
                    OR EXISTS (SELECT 1 FROM located_uris(source, aou.id, $10) LIMIT 1)
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
                            rad.sorter
                        ),
                        cmra.value
                    )
              FROM  (
                SELECT  v.source AS id,
                        c.id AS aid,
                        c.ctype AS attr,
                        c.code AS value
                  FROM  metabib.record_attr_vector_list v
                        JOIN config.coded_value_map c ON ( c.id = ANY( v.vlist ) )
                ) AS cmra
                    JOIN config.record_attr_definition rad ON (cmra.attr = rad.name)
                    JOIN sourcelist ON (cmra.id = sourcelist.source)
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
                SELECT  v.source AS id,
                        m.id AS aid,
                        m.attr AS attr,
                        m.value AS value
                  FROM  metabib.record_attr_vector_list v
                        JOIN metabib.uncontrolled_record_attr_value m ON ( m.id = ANY( v.vlist ) )
                ) AS umra
                    JOIN config.record_attr_definition rad ON (umra.attr = rad.name)
                    JOIN sourcelist ON (umra.id = sourcelist.source)
                ORDER BY 1

            )foo(id,y)
        )
    )
$F$ LANGUAGE SQL STABLE;

COMMIT;

