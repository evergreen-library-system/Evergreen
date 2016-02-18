BEGIN;

SELECT evergreen.upgrade_deps_block_check('0954', :eg_version);

ALTER TABLE acq.fund_debit 
    ADD COLUMN invoice_entry INTEGER 
        REFERENCES acq.invoice_entry (id)
        ON DELETE SET NULL;

CREATE INDEX fund_debit_invoice_entry_idx ON acq.fund_debit (invoice_entry);
CREATE INDEX lineitem_detail_fund_debit_idx ON acq.lineitem_detail (fund_debit);

COMMIT;
