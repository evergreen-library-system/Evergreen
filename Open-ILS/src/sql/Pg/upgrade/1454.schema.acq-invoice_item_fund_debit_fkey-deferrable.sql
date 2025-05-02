BEGIN;

SELECT evergreen.upgrade_deps_block_check('1454', :eg_version);

ALTER TABLE acq.invoice_item ALTER CONSTRAINT invoice_item_fund_debit_fkey DEFERRABLE INITIALLY DEFERRED;

COMMIT;
