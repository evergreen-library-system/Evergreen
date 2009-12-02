BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0101');

-- represents a circ chain summary
CREATE TYPE action.circ_chain_summary AS (
    num_circs INTEGER,
    start_time TIMESTAMP WITH TIME ZONE,
    checkout_workstation TEXT,
    last_renewal_time TIMESTAMP WITH TIME ZONE, -- NULL if no renewals
    last_stop_fines TEXT,
    last_stop_fines_time TIMESTAMP WITH TIME ZONE,
    last_renewal_workstation TEXT, -- NULL if no renewals
    last_checkin_workstation TEXT,
    last_checkin_time TIMESTAMP WITH TIME ZONE,
    last_checkin_scan_time TIMESTAMP WITH TIME ZONE
);


CREATE OR REPLACE FUNCTION action.circ_chain ( ctx_circ_id INTEGER ) RETURNS SETOF action.circulation AS $$
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

CREATE OR REPLACE FUNCTION action.summarize_circ_chain ( ctx_circ_id INTEGER ) RETURNS action.circ_chain_summary AS $$

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


COMMIT;


