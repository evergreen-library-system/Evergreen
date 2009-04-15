-- Testing purposes only
-- Removes all traces of a purchase order, including the PO, lineitems, 
-- lineitem_details, bibs, copies, callnumbers, and debits

CREATE OR REPLACE FUNCTION acq.purge_po (po_id INT) RETURNS VOID AS $$
DECLARE
    li RECORD;
BEGIN
    FOR li IN SELECT * FROM acq.lineitem WHERE purchase_order = po_id LOOP

        DELETE FROM asset.copy WHERE call_number IN (
            SELECT id FROM asset.call_number WHERE record = li.eg_bib_id);
        DELETE FROM asset.call_number WHERE record = li.eg_bib_id;
        DELETE FROM biblio.record_entry WHERE id = li.eg_bib_id;

        DELETE FROM acq.fund_debit WHERE id in (
            SELECT fund_debit FROM acq.lineitem_detail WHERE lineitem = li.id);
        DELETE FROM acq.lineitem_detail WHERE lineitem = li.id;
        IF li.picklist IS NULL THEN
            DELETE FROM acq.lineitem_attr WHERE lineitem = li.id;
            DELETE from acq.lineitem WHERE id = li.id;
        ELSE
            UPDATE acq.lineitem SET purchase_order = NULL, eg_bib_id = NULL, state = 'new' WHERE id = li.id;
        END IF;
    END LOOP;

    DELETE FROM acq.purchase_order WHERE id = po_id;
END;
$$ LANGUAGE plpgsql;
