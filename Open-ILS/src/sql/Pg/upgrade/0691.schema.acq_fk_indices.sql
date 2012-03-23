BEGIN;

SELECT evergreen.upgrade_deps_block_check('0691', :eg_version);

CREATE INDEX poi_po_idx ON acq.po_item (purchase_order);

CREATE INDEX ie_inv_idx on acq.invoice_entry (invoice);
CREATE INDEX ie_po_idx on acq.invoice_entry (purchase_order);
CREATE INDEX ie_li_idx on acq.invoice_entry (lineitem);

CREATE INDEX ii_inv_idx on acq.invoice_item (invoice);
CREATE INDEX ii_po_idx on acq.invoice_item (purchase_order);
CREATE INDEX ii_poi_idx on acq.invoice_item (po_item);

COMMIT;
