DROP FUNCTION action.usr_visible_circ_copies( INTEGER ); -- Ignore me if I fail

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0324'); 

-- returns the distinct set of target copy IDs from a user's visible circulation history
CREATE OR REPLACE FUNCTION action.usr_visible_circ_copies( INTEGER ) RETURNS SETOF BIGINT AS $$
    SELECT DISTINCT(target_copy) FROM action.usr_visible_circs($1)
$$ LANGUAGE SQL;

COMMIT;
