-- Add missing FROM clause entry to asset.opac_lasso_record_copy_count

BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

CREATE OR REPLACE FUNCTION asset.opac_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                org_list,
                available_statuses,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy AND av.record = rid)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

COMMIT;
