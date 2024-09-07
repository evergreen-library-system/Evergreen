BEGIN;

SELECT evergreen.upgrade_deps_block_check('1431', :eg_version);

--Add the new information used to calculate available_copy_ratio to the stats the function sends out
DROP TYPE IF EXISTS action.hold_stats CASCADE;
CREATE TYPE action.hold_stats AS (
    hold_count              INT,
    competing_hold_count    INT,
    copy_count              INT,
    available_count         INT,
    total_copy_ratio        FLOAT,
    available_copy_ratio    FLOAT
);

--copy_id is a numeric id from asset.copy.
--A copy is treated as unavailable if it is still age protected and belongs to a different org unit
CREATE OR REPLACE FUNCTION action.copy_related_hold_stats (copy_id BIGINT) RETURNS action.hold_stats AS $func$
DECLARE
    output                  action.hold_stats%ROWTYPE;
    hold_count              INT := 0;
    competing_hold_count    INT := 0;
    copy_count              INT := 0;
    available_count         INT := 0;
    copy                    RECORD;
    hold                    RECORD;
BEGIN

    output.hold_count := 0;
    output.competing_hold_count := 0;
    output.copy_count := 0;
    output.available_count := 0;

    --Find all unique holds considering our copy
    CREATE TEMPORARY TABLE copy_holds_tmp AS 
        SELECT  DISTINCT m.hold, m.target_copy, h.pickup_lib, h.request_lib, h.requestor, h.usr
        FROM  action.hold_copy_map m
                JOIN action.hold_request h ON (m.hold = h.id)
        WHERE m.target_copy = copy_id
                AND NOT h.frozen;
        

    --Count how many holds there are
    SELECT  COUNT( DISTINCT m.hold ) INTO hold_count
       FROM  action.hold_copy_map m
             JOIN action.hold_request h ON (m.hold = h.id)
       WHERE m.target_copy = copy_id
             AND NOT h.frozen;

    output.hold_count := hold_count;

    --Count how many holds looking at our copy would be allowed to be fulfilled by our copy (are valid competition for our copy)
    CREATE TEMPORARY TABLE competing_holds AS
        SELECT *
        FROM copy_holds_tmp
        WHERE (SELECT success FROM action.hold_request_permit_test(pickup_lib, request_lib, copy_id, usr, requestor) LIMIT 1);

    SELECT COUNT(*) INTO competing_hold_count
    FROM competing_holds;

    output.competing_hold_count := competing_hold_count;

    IF output.hold_count > 0 THEN

        --Get the total count separately in case the competing hold we find the available on is old and missed a target
        SELECT INTO output.copy_count COUNT(DISTINCT m.target_copy)
        FROM  action.hold_copy_map m
                JOIN asset.copy acp ON (m.target_copy = acp.id)
                JOIN action.hold_request h ON (m.hold = h.id)
        WHERE m.hold IN ( SELECT DISTINCT hold_copy_map.hold FROM action.hold_copy_map WHERE target_copy = copy_id ) 
        AND NOT h.frozen
        AND NOT acp.deleted;

        --'Available' means available to the same people, so we use the competing hold to test if it's available to them
        SELECT INTO hold * FROM competing_holds ORDER BY competing_holds.hold DESC LIMIT 1;

        --Assuming any competing hold can be placed on the same copies as every competing hold ; can't afford a nested loop
        --Could maybe be broken by a hold from a user with superpermissions ignoring age protections? Still using available status first as fallback.
        FOR copy IN
            SELECT DISTINCT m.target_copy AS id, acp.status
            FROM competing_holds c
                JOIN action.hold_copy_map m ON c.hold = m.hold
                JOIN asset.copy acp ON m.target_copy = acp.id
        LOOP
            --Check age protection by checking if the hold is permitted with hold_permit_test
            --Hopefully hold_matrix never needs to know if an item could circulate or there'd be an infinite loop
            IF (copy.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available)) AND
                (SELECT success FROM action.hold_request_permit_test(hold.pickup_lib, hold.request_lib, copy.id, hold.usr, hold.requestor) LIMIT 1) THEN
                    output.available_count := output.available_count + 1;
            END IF;
        END LOOP;

        output.total_copy_ratio = output.copy_count::FLOAT / output.hold_count::FLOAT;
        IF output.competing_hold_count > 0 THEN
            output.available_copy_ratio = output.available_count::FLOAT / output.competing_hold_count::FLOAT;
        END IF;
    END IF;
    
    --Clean up our temporary tables
    DROP TABLE copy_holds_tmp;
    DROP TABLE competing_holds;

    RETURN output;

END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
