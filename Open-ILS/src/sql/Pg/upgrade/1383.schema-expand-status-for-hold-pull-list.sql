BEGIN;

SELECT evergreen.upgrade_deps_block_check('1383', :eg_version);

DROP INDEX IF EXISTS asset.cp_available_by_circ_lib_idx;

DROP INDEX IF EXISTS serial.unit_available_by_circ_lib_idx;

CREATE INDEX cp_extant_by_circ_lib_idx ON asset.copy(circ_lib) WHERE deleted = FALSE OR deleted IS FALSE;

CREATE INDEX unit_extant_by_circ_lib_idx ON serial.unit(circ_lib) WHERE deleted = FALSE OR deleted IS FALSE;

CREATE OR REPLACE FUNCTION action.copy_related_hold_stats (copy_id BIGINT) RETURNS action.hold_stats AS $func$
DECLARE
    output          action.hold_stats%ROWTYPE;
    hold_count      INT := 0;
    copy_count      INT := 0;
    available_count INT := 0;
    hold_map_data   RECORD;
BEGIN

    output.hold_count := 0;
    output.copy_count := 0;
    output.available_count := 0;

    SELECT  COUNT( DISTINCT m.hold ) INTO hold_count
      FROM  action.hold_copy_map m
            JOIN action.hold_request h ON (m.hold = h.id)
      WHERE m.target_copy = copy_id
            AND NOT h.frozen;

    output.hold_count := hold_count;

    IF output.hold_count > 0 THEN
        FOR hold_map_data IN
            SELECT  DISTINCT m.target_copy,
                    acp.status
              FROM  action.hold_copy_map m
                    JOIN asset.copy acp ON (m.target_copy = acp.id)
                    JOIN action.hold_request h ON (m.hold = h.id)
              WHERE m.hold IN ( SELECT DISTINCT hold FROM action.hold_copy_map WHERE target_copy = copy_id ) AND NOT h.frozen
        LOOP
            output.copy_count := output.copy_count + 1;
            IF hold_map_data.status IN (SELECT id from config.copy_status where holdable and is_available) THEN
                output.available_count := output.available_count + 1;
            END IF;
        END LOOP;
        output.total_copy_ratio = output.copy_count::FLOAT / output.hold_count::FLOAT;
        output.available_copy_ratio = output.available_count::FLOAT / output.hold_count::FLOAT;

    END IF;

    RETURN output;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available)
                   THEN 1 ELSE 0 END ),
                SUM( CASE WHEN cl.opac_visible AND cp.opac_visible THEN 1 ELSE 0 END),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_ou_metarecord_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;


COMMIT;
