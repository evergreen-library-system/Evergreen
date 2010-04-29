BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0247'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel',
        oils_i18n_gettext(
            'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel',
            'CAT: Delete bib if all copies are deleted via Acquisitions lineitem cancellation.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel',
            'CAT: Delete bib if all copies are deleted via Acquisitions lineitem cancellation.', 
            'coust', 
            'description'),
        'bool'
);

COMMIT;
