
BEGIN;
SELECT evergreen.upgrade_deps_block_check('0751', :eg_version);

INSERT INTO acq.cancel_reason (keep_debits, id, org_unit, label, description) 
    VALUES (
        'f', 
        1007, 
        1, 
        'Not accepted', 
        'This line item is not accepted by the seller.'
    );

COMMIT;

