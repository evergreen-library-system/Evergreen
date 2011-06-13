-- Evergreen DB patch 0558.schema.in-db_unapi_copy_related_visibility-2.sql
--
-- Bring in-db unAPI opac visibility info up to date with (and a little beyond) ea3b8857d08b8a9050e763f8084c841e8df9a473
--
BEGIN;


INSERT INTO config.upgrade_log (version) VALUES ('0558'); -- miker

CREATE OR REPLACE FUNCTION unapi.ccs ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name status,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident
                    holdable,
                    opac_visible
                ),
                name
            )
      FROM  config.copy_status
      WHERE id = $1;
$F$ LANGUAGE SQL;

COMMIT;
