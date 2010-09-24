-- Apply in an update script some fixes that were previously applied only
-- to the base installation script 090.schema.action.sql.

-- Also fix a typo: INTEVAL -> INTERVAL

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0418'); -- Scott McKellar

CREATE OR REPLACE FUNCTION action.purge_circulations () RETURNS INT AS $func$
DECLARE
    usr_keep_age    actor.usr_setting%ROWTYPE;
    usr_keep_start  actor.usr_setting%ROWTYPE;
    org_keep_age    INTERVAL;
    org_keep_count  INT;

    keep_age        INTERVAL;

    target_acp      RECORD;
    circ_chain_head action.circulation%ROWTYPE;
    circ_chain_tail action.circulation%ROWTYPE;

    purge_position  INT;
    count_purged    INT;
BEGIN

    count_purged := 0;

    SELECT value::INTERVAL INTO org_keep_age FROM config.global_flag WHERE name = 'history.circ.retention_age' AND enabled;

    SELECT value::INT INTO org_keep_count FROM config.global_flag WHERE name = 'history.circ.retention_count' AND enabled;
    IF org_keep_count IS NULL THEN
        RETURN count_purged; -- Gimme a count to keep, or I keep them all, forever
    END IF;

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
        purge_position := 0;
        -- And, for those, select circs that are finished and older than keep_age
        FOR circ_chain_head IN
            SELECT  *
              FROM  action.circulation
              WHERE target_copy = target_acp.target_copy
                    AND parent_circ IS NULL
              ORDER BY xact_start
        LOOP

            -- Stop once we've purged enough circs to hit org_keep_count
            EXIT WHEN target_acp.total_real_circs - purge_position <= org_keep_count;

            SELECT * INTO circ_chain_tail FROM action.circ_chain(circ_chain_head.id) ORDER BY xact_start DESC LIMIT 1;
            EXIT WHEN circ_chain_tail.xact_finish IS NULL;

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
                keep_age := COALESCE( org_keep_age::INTERVAL, '2000 years'::INTERVAL );
            END IF;

            EXIT WHEN AGE(NOW(), circ_chain_tail.xact_finish) < keep_age;

            -- We've passed the purging tests, purge the circ chain starting at the end
            DELETE FROM action.circulation WHERE id = circ_chain_tail.id;
            WHILE circ_chain_tail.parent_circ IS NOT NULL LOOP
                SELECT * INTO circ_chain_tail FROM action.circulation WHERE id = circ_chain_tail.parent_circ;
                DELETE FROM action.circulation WHERE id = circ_chain_tail.id;
            END LOOP;

            count_purged := count_purged + 1;
            purge_position := purge_position + 1;

        END LOOP;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;


COMMIT;
