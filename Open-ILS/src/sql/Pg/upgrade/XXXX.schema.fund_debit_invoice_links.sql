BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE acq.fund_debit 
    ADD COLUMN invoice_entry INTEGER 
        REFERENCES acq.invoice_entry (id)
        ON DELETE SET NULL;

COMMIT;
