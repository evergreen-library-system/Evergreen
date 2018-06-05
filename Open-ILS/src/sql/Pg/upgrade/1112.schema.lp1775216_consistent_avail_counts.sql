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
        WITH available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available)
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                SUM( CASE WHEN cl.opac_visible AND cp.opac_visible THEN 1 ELSE 0 END),
                trans
          FROM
                available_statuses,
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$function$;
