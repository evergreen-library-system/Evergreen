BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('0798', :eg_version); -- tsbere/Dyrcona/dbwells

INSERT INTO config.global_flag (name, label)
    VALUES (
        'history.circ.retention_uses_last_finished',
        oils_i18n_gettext(
            'history.circ.retention_uses_last_finished',
            'Historical Circulations use most recent xact_finish date instead of last circ''s.',
            'cgf',
            'label'
        )
    ),(
        'history.circ.retention_age_is_min',
        oils_i18n_gettext(
            'history.circ.retention_age_is_min',
            'Historical Circulations are kept for global retention age at a minimum, regardless of user preferences.',
            'cgf',
            'label'
        )
    );


-- Drop old variants
DROP FUNCTION IF EXISTS action.circ_chain(INTEGER);
DROP FUNCTION IF EXISTS action.summarize_circ_chain(INTEGER);

CREATE OR REPLACE FUNCTION action.circ_chain ( ctx_circ_id BIGINT ) RETURNS SETOF action.circulation AS $$
DECLARE
    tmp_circ action.circulation%ROWTYPE;
    circ_0 action.circulation%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.circulation WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.circulation WHERE id = tmp_circ.parent_circ;
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
        SELECT INTO tmp_circ * FROM action.circulation WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.summarize_circ_chain ( ctx_circ_id BIGINT ) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.circulation%ROWTYPE;

    -- last circ in the chain
    circ_n action.circulation%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.circulation%ROWTYPE;

BEGIN
    
    chain.num_circs := 0;
    FOR tmp_circ IN SELECT * FROM action.circ_chain(ctx_circ_id) LOOP

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

CREATE OR REPLACE FUNCTION action.purge_circulations () RETURNS INT AS $func$
DECLARE
    usr_keep_age    actor.usr_setting%ROWTYPE;
    usr_keep_start  actor.usr_setting%ROWTYPE;
    org_keep_age    INTERVAL;
    org_use_last    BOOL = false;
    org_age_is_min  BOOL = false;
    org_keep_count  INT;

    keep_age        INTERVAL;

    target_acp      RECORD;
    circ_chain_head action.circulation%ROWTYPE;
    circ_chain_tail action.circulation%ROWTYPE;

    count_purged    INT;
    num_incomplete  INT;

    last_finished   TIMESTAMP WITH TIME ZONE;
BEGIN

    count_purged := 0;

    SELECT value::INTERVAL INTO org_keep_age FROM config.global_flag WHERE name = 'history.circ.retention_age' AND enabled;

    SELECT value::INT INTO org_keep_count FROM config.global_flag WHERE name = 'history.circ.retention_count' AND enabled;
    IF org_keep_count IS NULL THEN
        RETURN count_purged; -- Gimme a count to keep, or I keep them all, forever
    END IF;

    SELECT enabled INTO org_use_last FROM config.global_flag WHERE name = 'history.circ.retention_uses_last_finished';
    SELECT enabled INTO org_age_is_min FROM config.global_flag WHERE name = 'history.circ.retention_age_is_min';

    -- First, find copies with more than keep_count non-renewal circs
    FOR target_acp IN
        SELECT  target_copy,
                COUNT(*) AS total_real_circs
          FROM  action.circulation
          WHERE parent_circ IS NULL
                AND xact_finish IS NOT NULL
          GROUP BY target_copy
          HAVING COUNT(*) > org_keep_count
    LOOP
        -- And, for those, select circs that are finished and older than keep_age
        FOR circ_chain_head IN
            -- For reference, the subquery uses a window function to order the circs newest to oldest and number them
            -- The outer query then uses that information to skip the most recent set the library wants to keep
            -- End result is we don't care what order they come out in, as they are all potentials for deletion.
            SELECT ac.* FROM action.circulation ac JOIN (
              SELECT  rank() OVER (ORDER BY xact_start DESC), ac.id
                FROM  action.circulation ac
                WHERE ac.target_copy = target_acp.target_copy
                  AND ac.parent_circ IS NULL
                ORDER BY ac.xact_start ) ranked USING (id)
                WHERE ranked.rank > org_keep_count
        LOOP

            SELECT * INTO circ_chain_tail FROM action.circ_chain(circ_chain_head.id) ORDER BY xact_start DESC LIMIT 1;
            SELECT COUNT(CASE WHEN xact_finish IS NULL THEN 1 ELSE NULL END), MAX(xact_finish) INTO num_incomplete, last_finished FROM action.circ_chain(circ_chain_head.id);
            CONTINUE WHEN circ_chain_tail.xact_finish IS NULL OR num_incomplete > 0;

            IF NOT org_use_last THEN
                last_finished := circ_chain_tail.xact_finish;
            END IF;

            -- Now get the user settings, if any, to block purging if the user wants to keep more circs
            usr_keep_age.value := NULL;
            SELECT * INTO usr_keep_age FROM actor.usr_setting WHERE usr = circ_chain_head.usr AND name = 'history.circ.retention_age';

            usr_keep_start.value := NULL;
            SELECT * INTO usr_keep_start FROM actor.usr_setting WHERE usr = circ_chain_head.usr AND name = 'history.circ.retention_start';

            IF usr_keep_age.value IS NOT NULL AND usr_keep_start.value IS NOT NULL THEN
                IF oils_json_to_text(usr_keep_age.value)::INTERVAL > AGE(NOW(), oils_json_to_text(usr_keep_start.value)::TIMESTAMPTZ) THEN
                    keep_age := AGE(NOW(), oils_json_to_text(usr_keep_start.value)::TIMESTAMPTZ);
                ELSE
                    keep_age := oils_json_to_text(usr_keep_age.value)::INTERVAL;
                END IF;
            ELSIF usr_keep_start.value IS NOT NULL THEN
                keep_age := AGE(NOW(), oils_json_to_text(usr_keep_start.value)::TIMESTAMPTZ);
            ELSE
                keep_age := COALESCE( org_keep_age, '2000 years'::INTERVAL );
            END IF;

            IF org_age_is_min THEN
                keep_age := GREATEST( keep_age, org_keep_age );
            END IF;

            CONTINUE WHEN AGE(NOW(), last_finished) < keep_age;

            -- We've passed the purging tests, purge the circ chain starting at the end
            -- A trigger should auto-purge the rest of the chain.
            DELETE FROM action.circulation WHERE id = circ_chain_tail.id;

            count_purged := count_purged + 1;

        END LOOP;
    END LOOP;

    return count_purged;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
