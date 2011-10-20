-- Evergreen DB patch 0673.data.acq-cancel-reason-cleanup.sql
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0673', :eg_version);

DELETE FROM
    acq.cancel_reason
WHERE
    -- any entries with id >= 2000 were added locally.  
    id < 2000 

    -- these cancel_reason's are actively used by the system
    AND id NOT IN (1, 2, 3, 1002, 1003, 1004, 1005, 1010, 1024, 1211, 1221, 1246, 1283)

    -- don't delete any cancel_reason's that may be in use locally
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.user_request WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.purchase_order WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.lineitem WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.lineitem_detail WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.acq_lineitem_history WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.acq_purchase_order_history WHERE cancel_reason IS NOT NULL);

COMMIT;
