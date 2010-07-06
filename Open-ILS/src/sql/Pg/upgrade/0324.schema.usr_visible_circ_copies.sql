BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0324'); 

-- returns the distinct set of target copy IDs from a user's visible circulation history
CREATE OR REPLACE FUNCTION action.usr_visible_circ_copies( user_id INTEGER ) RETURNS SETOF INTEGER AS $$
    DECLARE
        copy INTEGER;
    BEGIN
        FOR copy IN SELECT DISTINCT(target_copy) FROM action.usr_visible_circs(user_id) LOOP
            RETURN NEXT copy;
        END LOOP;
    END;
$$ LANGUAGE plpgsql;

COMMIT;
