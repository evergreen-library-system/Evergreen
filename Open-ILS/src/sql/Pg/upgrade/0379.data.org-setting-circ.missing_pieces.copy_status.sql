BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0379'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class ) VALUES (
        'circ.missing_pieces.copy_status',
        oils_i18n_gettext(
            'circ.missing_pieces.copy_status',
            'Circulation: Item Status for Missing Pieces', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'circ.missing_pieces.copy_status',
            'This is the Item Status to use for items that have been marked or scanned as having Missing Pieces.  In absense of this setting, the Damaged status is used.',
            'coust', 
            'description'),
        'link',
        'ccs'
);

COMMIT;
