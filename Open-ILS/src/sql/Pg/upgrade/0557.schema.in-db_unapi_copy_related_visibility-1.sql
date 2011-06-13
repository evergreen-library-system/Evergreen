-- Evergreen DB patch 0557.schmea.in-db_unapi_copy_related_visibility-1.sql
--
-- Bring in-db unAPI opac visibility info up to date with (and a little beyond) ea3b8857d08b8a9050e763f8084c841e8df9a473
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0557', :eg_version);

CREATE OR REPLACE FUNCTION unapi.acl ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name location,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident
                    holdable,
                    opac_visible,
                    label_prefix AS prefix,
                    label_suffix AS suffix
                ),
                name
            )
      FROM  asset.copy_location
      WHERE id = $1;
$F$ LANGUAGE SQL;

COMMIT;
