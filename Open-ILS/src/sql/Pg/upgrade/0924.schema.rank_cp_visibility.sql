-- Evergreen DB patch 0924.schema.rank_cp_visibility.sql
--
-- rank_cp() is meant to return the most-available copies, so it needs to
-- factor in the opac_visible flag on the copies themselves
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0924', :eg_version);

-- function is being expanded and renamed, so drop the old version
DROP FUNCTION IF EXISTS evergreen.rank_cp_status(INT);

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
        SELECT acn.id, aou.name, acn.label_sortkey,
            evergreen.rank_cp(acp),
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN descendants AS aou ON (acp.circ_lib = aou.id)
        WHERE acn.record = ANY ($1)
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
            AND CASE WHEN ('exclude_invisible_acn' = ANY($7)) THEN 
                EXISTS (
                    SELECT 1 
                    FROM asset.opac_visible_copies 
                    WHERE copy_id = acp.id AND record = acn.record
                ) ELSE TRUE END
        GROUP BY acn.id, evergreen.rank_cp(acp), aou.name, acn.label_sortkey, aou.id
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
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8),
                    CASE 
                        WHEN ('acp' = ANY ($4)) THEN
                            CASE WHEN $6 IS NOT NULL THEN
                                XMLELEMENT( name copies,
                                    (SELECT XMLAGG(acp ORDER BY rank_avail) FROM (
                                        SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
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
                                        SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
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
                        (SELECT XMLAGG(auri) FROM (SELECT unapi.auri(uri,'xml','uri', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE call_number = acn.id)x)
                    ),
                    unapi.acnp( acn.prefix, 'marcxml', 'prefix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                    unapi.acns( acn.suffix, 'marcxml', 'suffix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( acn.record, 'marcxml', 'record', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END
                ) AS x
          FROM  asset.call_number acn
                JOIN actor.org_unit o ON (o.id = acn.owning_lib)
          WHERE acn.id = $1
              AND acn.deleted IS FALSE
          GROUP BY acn.id, o.shortname, o.opac_visible, deleted, label, label_sortkey, label_class, owning_lib, record, acn.prefix, acn.suffix;
$F$ LANGUAGE SQL STABLE;

COMMIT;
