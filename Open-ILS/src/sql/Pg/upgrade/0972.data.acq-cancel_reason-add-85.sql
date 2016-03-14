BEGIN;

SELECT evergreen.upgrade_deps_block_check('0972', :eg_version); -- jstompro/gmcharlt

-- LP#1550495 - Add Baker&Taylor EDI Quantity Cancel Code
-- Insert EDI Cancel Reason 85 (1200 + 85 = 1285) if it doesn't already exist
INSERT INTO acq.cancel_reason 
   (org_unit, keep_debits, id, label, description)
   SELECT 
     1, 'f',( 85+1200),
     oils_i18n_gettext(1285, 'Canceled: By Vendor', 'acqcr', 'label'),
     oils_i18n_gettext(1285, 'Line item canceled by vendor', 'acqcr', 'description')
   WHERE NOT EXISTS (
    SELECT 1 FROM acq.cancel_reason where id=(85+1200)
   );


COMMIT;
