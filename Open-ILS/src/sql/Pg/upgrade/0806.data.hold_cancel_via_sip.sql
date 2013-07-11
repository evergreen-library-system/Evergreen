BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0806', :eg_version);

INSERT INTO action.hold_request_cancel_cause (id,label) 
    VALUES (7,'Patron via SIP');

COMMIT;
