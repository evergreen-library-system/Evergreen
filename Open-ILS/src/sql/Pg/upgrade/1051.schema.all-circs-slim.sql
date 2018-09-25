BEGIN;

SELECT evergreen.upgrade_deps_block_check('1051', :eg_version);

CREATE OR REPLACE VIEW action.all_circulation_slim AS
    SELECT
        id,
        usr,
        xact_start,
        xact_finish,
        unrecovered,
        target_copy,
        circ_lib,
        circ_staff,
        checkin_staff,
        checkin_lib,
        renewal_remaining,
        grace_period,
        due_date,
        stop_fines_time,
        checkin_time,
        create_time,
        duration,
        fine_interval,
        recurring_fine,
        max_fine,
        phone_renewal,
        desk_renewal,
        opac_renewal,
        duration_rule,
        recurring_fine_rule,
        max_fine_rule,
        stop_fines,
        workstation,
        checkin_workstation,
        copy_location,
        checkin_scan_time,
        parent_circ
    FROM action.circulation
UNION ALL
    SELECT
        id,
        NULL AS usr,
        xact_start,
        xact_finish,
        unrecovered,
        target_copy,
        circ_lib,
        circ_staff,
        checkin_staff,
        checkin_lib,
        renewal_remaining,
        grace_period,
        due_date,
        stop_fines_time,
        checkin_time,
        create_time,
        duration,
        fine_interval,
        recurring_fine,
        max_fine,
        phone_renewal,
        desk_renewal,
        opac_renewal,
        duration_rule,
        recurring_fine_rule,
        max_fine_rule,
        stop_fines,
        workstation,
        checkin_workstation,
        copy_location,
        checkin_scan_time,
        parent_circ
    FROM action.aged_circulation
;

DROP FUNCTION action.summarize_all_circ_chain(INTEGER);
DROP FUNCTION action.all_circ_chain(INTEGER);

CREATE OR REPLACE FUNCTION action.all_circ_chain (ctx_circ_id INTEGER) 
    RETURNS SETOF action.all_circulation_slim AS $$
DECLARE
    tmp_circ action.all_circulation_slim%ROWTYPE;
    circ_0 action.all_circulation_slim%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.all_circulation_slim WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
            WHERE id = tmp_circ.parent_circ;
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        circ_0 := tmp_circ;
    END LOOP;

    -- now send the circs to the caller, oldest to newest
    tmp_circ := circ_0;
    WHILE TRUE LOOP
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        RETURN NEXT tmp_circ;
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
            WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.summarize_all_circ_chain 
    (ctx_circ_id INTEGER) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.all_circulation_slim%ROWTYPE;

    -- last circ in the chain
    circ_n action.all_circulation_slim%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.all_circulation_slim%ROWTYPE;

BEGIN
    
    chain.num_circs := 0;
    FOR tmp_circ IN SELECT * FROM action.all_circ_chain(ctx_circ_id) LOOP

        IF chain.num_circs = 0 THEN
            circ_0 := tmp_circ;
        END IF;

        chain.num_circs := chain.num_circs + 1;
        circ_n := tmp_circ;
    END LOOP;

    chain.start_time := circ_0.xact_start;
    chain.last_stop_fines := circ_n.stop_fines;
    chain.last_stop_fines_time := circ_n.stop_fines_time;
    chain.last_checkin_time := circ_n.checkin_time;
    chain.last_checkin_scan_time := circ_n.checkin_scan_time;
    SELECT INTO chain.checkout_workstation name FROM actor.workstation WHERE id = circ_0.workstation;
    SELECT INTO chain.last_checkin_workstation name FROM actor.workstation WHERE id = circ_n.checkin_workstation;

    IF chain.num_circs > 1 THEN
        chain.last_renewal_time := circ_n.xact_start;
        SELECT INTO chain.last_renewal_workstation name FROM actor.workstation WHERE id = circ_n.workstation;
    END IF;

    RETURN chain;

END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION rating.percent_time_circulating(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT bib,
            SUM(COALESCE(circ_time,0))::NUMERIC / SUM(age)::NUMERIC
      FROM  (SELECT cn.record AS bib,
                    cp.id,
                    EXTRACT( EPOCH FROM AGE(cp.active_date) ) + 1 AS age,
                    SUM(  -- time copy spent circulating
                        EXTRACT(
                            EPOCH FROM
                            AGE(
                                COALESCE(circ.checkin_time, circ.stop_fines_time, NOW()),
                                circ.xact_start
                            )
                        )
                    )::NUMERIC AS circ_time
              FROM  asset.copy cp
                    JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
                    JOIN asset.call_number cn ON (cn.id = cp.call_number)
                    LEFT JOIN action.all_circulation_slim circ ON (
                        circ.target_copy = cp.id
                        AND stop_fines NOT IN (
                            'LOST',
                            'LONGOVERDUE',
                            'CLAIMSRETURNED',
                            'LONGOVERDUE'
                        )
                        AND NOT (
                            checkin_time IS NULL AND
                            stop_fines = 'MAXFINES'
                        )
                    )
              WHERE cn.owning_lib = ANY (badge.orgs)
                    AND cp.active_date IS NOT NULL
                    -- Next line requires that copies with no circs (circ.id IS NULL) also not be deleted
                    AND ((circ.id IS NULL AND NOT cp.deleted) OR circ.id IS NOT NULL)
              GROUP BY 1,2,3
            ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;


-- ROLLBACK;
COMMIT;

