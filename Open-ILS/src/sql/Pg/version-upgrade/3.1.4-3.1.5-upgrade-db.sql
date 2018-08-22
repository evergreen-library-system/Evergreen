--Upgrade Script for 3.1.4 to 3.1.5
\set eg_version '''3.1.5'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.1.5', :eg_version);
SELECT evergreen.upgrade_deps_block_check('1119', :eg_version);

CREATE OR REPLACE FUNCTION asset.staff_ou_record_copy_count(org integer, rid bigint)
 RETURNS TABLE(depth integer, org_unit integer, visible bigint, available bigint, unshadow bigint, transcendant integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        WITH available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
            cp AS(
                SELECT  cp.id,
                        (cp.status = ANY (available_statuses.ids))::INT as available,
                        (cl.opac_visible AND cp.opac_visible)::INT as opac_visible
                  FROM
                        available_statuses,
                        actor.org_unit_descendants(ans.id) d
                        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                        JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
            ),
            peer AS (
                SELECT  cp.id,
                        (cp.status = ANY  (available_statuses.ids))::INT as available,
                        (cl.opac_visible AND cp.opac_visible)::INT as opac_visible
                FROM
                        available_statuses,
                        actor.org_unit_descendants(ans.id) d
                        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                        JOIN biblio.peer_bib_copy_map bp ON (bp.peer_record = rid AND bp.target_copy = cp.id)
            )
        SELECT ans.depth, ans.id, count(id), sum(x.available::int), sum(x.opac_visible::int), trans
        FROM ((select * from cp) union (select * from peer)) x
        GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;
    RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION asset.opac_ou_record_copy_count(org integer, rid bigint)
 RETURNS TABLE(depth integer, org_unit integer, visible bigint, available bigint, unshadow bigint, transcendant integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                available_statuses,
                org_list,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy AND av.record = rid)
                JOIN asset.call_number cn ON (cp.call_number = cn.id AND not cn.deleted)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$function$;

COMMIT;
