BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0078');

UPDATE config.org_unit_setting_type 
    SET 
        name = 'circ.claim_return.copy_status', 
        fm_class = 'ccs', 
        datatype = 'link', 
        label = 'Claim Return Copy Status', 
        description = 'Claims returned copies are put into this status.  Default is to leave the copy in the Checked Out status'
    WHERE 
        name = 'circ.claim_return.mark_missing';

COMMIT;

