BEGIN;

SELECT evergreen.upgrade_deps_block_check('1274', :eg_version);

CREATE INDEX poi_fund_debit_idx ON acq.po_item (fund_debit);
CREATE INDEX ii_fund_debit_idx ON acq.invoice_item (fund_debit);

COMMIT;
