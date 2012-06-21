

UPDATE config.standing_penalty 
    SET block_list = REPLACE(block_list, 'HOLD', 'HOLD|CAPTURE') 
    WHERE   
        -- STAFF_ penalties have names that match their block list
        name NOT LIKE 'STAFF_%' 
        -- belt & suspenders, also good for testing
        AND block_list NOT LIKE '%CAPTURE%'; 

 -- CIRC|FULFILL is now the same as CIRC previously was by itself
UPDATE config.standing_penalty 
    SET block_list = REPLACE(block_list, 'CIRC', 'CIRC|FULFILL') 
    WHERE   
        -- STAFF_ penalties have names that match their block list
        name NOT LIKE 'STAFF_%' 
        -- belt & suspenders, also good for testing
        AND block_list NOT LIKE '%FULFILL%'; 


