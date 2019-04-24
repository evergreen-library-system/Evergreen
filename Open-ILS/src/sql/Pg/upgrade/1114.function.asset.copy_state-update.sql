BEGIN;

SELECT evergreen.upgrade_deps_block_check('1114', :eg_version);

CREATE OR REPLACE FUNCTION asset.copy_state (cid BIGINT) RETURNS TEXT AS $$
DECLARE
    last_circ_stop      TEXT;
    the_copy        asset.copy%ROWTYPE;
BEGIN

    SELECT * INTO the_copy FROM asset.copy WHERE id = cid;
    IF NOT FOUND THEN RETURN NULL; END IF;

    IF the_copy.status = 3 THEN -- Lost
        RETURN 'LOST';
    ELSIF the_copy.status = 4 THEN -- Missing
        RETURN 'MISSING';
    ELSIF the_copy.status = 14 THEN -- Damaged
        RETURN 'DAMAGED';
    ELSIF the_copy.status = 17 THEN -- Lost and paid
        RETURN 'LOST_AND_PAID';
    END IF;

    SELECT stop_fines INTO last_circ_stop
      FROM  action.circulation
      WHERE target_copy = cid AND checkin_time IS NULL
      ORDER BY xact_start DESC LIMIT 1;

    IF FOUND THEN
        IF last_circ_stop IN (
            'CLAIMSNEVERCHECKEDOUT',
            'CLAIMSRETURNED',
            'LONGOVERDUE'
        ) THEN
            RETURN last_circ_stop;
        END IF;
    END IF;

    RETURN 'NORMAL';
END;
$$ LANGUAGE PLPGSQL;

COMMIT;

