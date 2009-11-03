BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0067');

CREATE TYPE action.hold_stats AS (
    hold_count              INT,
    copy_count              INT,
    available_count         INT,
    total_copy_ratio        FLOAT,
    available_copy_ratio    FLOAT
);

CREATE OR REPLACE FUNCTION action.copy_related_hold_stats (copy_id INT) RETURNS action.hold_stats AS $func$
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
            IF hold_map_data.status IN (0,7,12) THEN
                output.available_count := output.available_count + 1;
            END IF;
        END LOOP;
        output.total_copy_ratio = output.copy_count::FLOAT / output.hold_count::FLOAT;
        output.available_copy_ratio = output.available_count::FLOAT / output.hold_count::FLOAT;

    END IF;

    RETURN output;

END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

