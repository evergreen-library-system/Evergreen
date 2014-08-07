BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0888', :eg_version);

DROP VIEW acq.lineitem_summary;

CREATE VIEW acq.lineitem_summary AS
    SELECT 
        li.id AS lineitem, 
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
            WHERE lineitem = li.id
        ) AS item_count,
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
            WHERE recv_time IS NOT NULL AND lineitem = li.id
        ) AS recv_count,
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
                JOIN acq.cancel_reason acqcr ON (acqcr.id = lid.cancel_reason)
            WHERE acqcr.keep_debits IS FALSE AND lineitem = li.id
        ) AS cancel_count,
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
                JOIN acq.cancel_reason acqcr ON (acqcr.id = lid.cancel_reason)
            WHERE acqcr.keep_debits IS TRUE AND lineitem = li.id
        ) AS delay_count,
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
                JOIN acq.fund_debit debit ON (lid.fund_debit = debit.id)
            WHERE NOT debit.encumbrance AND lineitem = li.id
        ) AS invoice_count,
        (
            SELECT COUNT(DISTINCT(lid.id)) 
            FROM acq.lineitem_detail lid
                JOIN acq.claim claim ON (claim.lineitem_detail = lid.id)
            WHERE lineitem = li.id
        ) AS claim_count,
        (
            SELECT (COUNT(lid.id) * li.estimated_unit_price)::NUMERIC(8,2)
            FROM acq.lineitem_detail lid
            WHERE lid.cancel_reason IS NULL AND lineitem = li.id
        ) AS estimated_amount,
        (
            SELECT SUM(debit.amount)::NUMERIC(8,2)
            FROM acq.lineitem_detail lid
                JOIN acq.fund_debit debit ON (lid.fund_debit = debit.id)
            WHERE debit.encumbrance AND lineitem = li.id
        ) AS encumbrance_amount,
        (
            SELECT SUM(debit.amount)::NUMERIC(8,2)
            FROM acq.lineitem_detail lid
                JOIN acq.fund_debit debit ON (lid.fund_debit = debit.id)
            WHERE NOT debit.encumbrance AND lineitem = li.id
        ) AS paid_amount

        FROM acq.lineitem AS li;

COMMIT;
