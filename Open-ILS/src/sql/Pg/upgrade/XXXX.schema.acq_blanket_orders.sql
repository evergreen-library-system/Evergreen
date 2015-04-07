BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE acq.invoice_item_type
    ADD COLUMN blanket BOOLEAN NOT NULL DEFAULT FALSE,
    ADD CONSTRAINT aiit_not_blanket_and_prorate
        CHECK (blanket IS FALSE OR prorate IS FALSE);

COMMIT;
