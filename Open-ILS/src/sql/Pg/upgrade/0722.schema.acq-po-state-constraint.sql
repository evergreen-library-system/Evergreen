-- Evergreen DB patch 0722.schema.acq-po-state-constraint.sql
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0722', :eg_version);

ALTER TABLE acq.purchase_order ADD CONSTRAINT valid_po_state 
    CHECK (state IN ('new','pending','on-order','received','cancelled'));

COMMIT;
