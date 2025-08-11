BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TYPE asset.holdable_part_count AS (id INT, label TEXT, holdable_count BIGINT);
CREATE OR REPLACE FUNCTION asset.count_holdable_parts_on_record (record_id BIGINT, pickup_lib INT DEFAULT NULL) RETURNS SETOF asset.holdable_part_count AS $func$
DECLARE 
    hard_boundary                   INT;
    orgs_within_hard_boundary       INT[];
BEGIN

    SELECT value INTO hard_boundary 
    FROM actor.org_unit_ancestor_setting('circ.hold_boundary.hard', pickup_lib)
    LIMIT 1;

    IF hard_boundary IS NOT NULL THEN
        SELECT ARRAY_AGG(id) INTO orgs_within_hard_boundary
        FROM actor.org_unit_descendants(pickup_lib, hard_boundary);
    END IF;

    RETURN QUERY 
    SELECT 
        bmp.id, 
        bmp.label, 
        COUNT(DISTINCT acp.id) AS holdable_count
    FROM asset.copy_part_map acpm
        JOIN biblio.monograph_part bmp ON acpm.part = bmp.id
        JOIN asset.copy acp ON acpm.target_copy = acp.id
        JOIN asset.call_number acn ON acp.call_number = acn.id
        JOIN biblio.record_entry bre ON acn.record = bre.id
        JOIN config.copy_status ccs ON acp.status = ccs.id
        JOIN asset.copy_location acpl ON acp.location = acpl.id
    WHERE
        NOT bmp.deleted
        AND (NOT acp.deleted AND acp.holdable)
        AND bre.id = record_id
        AND ccs.holdable
        AND acpl.holdable
        -- Check the circ_lib, but only when given a pickup lib for our hold AND we have hard boundary restrictions
        AND CASE WHEN orgs_within_hard_boundary IS NOT NULL THEN 
                acp.circ_lib = ANY(orgs_within_hard_boundary)
            ELSE TRUE 
            END
    GROUP BY 1, 2
    ORDER BY bmp.label_sortkey ASC;
END;
$func$ LANGUAGE plpgsql;

COMMIT;