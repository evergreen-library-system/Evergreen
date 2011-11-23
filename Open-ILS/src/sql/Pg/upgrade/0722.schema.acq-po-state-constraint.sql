-- Evergreen DB patch 0722.schema.acq-po-state-constraint.sql
--
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0722');

ALTER TABLE acq.purchase_order ADD CONSTRAINT valid_po_state 
    CHECK (state IN ('new','pending','on-order','received','cancelled'));

COMMIT;
