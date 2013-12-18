BEGIN;

SELECT evergreen.upgrade_deps_block_check('0850', :eg_version);

CREATE OR REPLACE FUNCTION unapi.mra ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name attributes,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@mra/' || mra.id AS id,
                        'tag:open-ils.org:U2@bre/' || mra.id AS record
                    ),
                    (SELECT XMLAGG(foo.y)
                      FROM (SELECT XMLELEMENT(
                                name field,
                                XMLATTRIBUTES(
                                    key AS name,
                                    cvm.value AS "coded-value",
                                    cvm.id AS "cvmid",
                                    rad.filter,
                                    rad.sorter
                                ),
                                x.value
                            )
                           FROM EACH(mra.attrs) AS x
                                JOIN config.record_attr_definition rad ON (x.key = rad.name)
                                LEFT JOIN config.coded_value_map cvm ON (cvm.ctype = x.key AND code = x.value)
                        )foo(y)
                    )
                )
          FROM  metabib.record_attr mra
          WHERE mra.id = $1;
$F$ LANGUAGE SQL STABLE;

COMMIT;
