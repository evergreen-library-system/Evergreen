BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0569'); --miker

CREATE OR REPLACE FUNCTION unapi.auri ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name uri,
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

COMMIT;
