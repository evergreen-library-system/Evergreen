BEGIN;

SELECT evergreen.upgrade_deps_block_check('0801', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'ui.patron.edit.ac.barcode.regex', 'gui',
    oils_i18n_gettext('ui.patron.edit.ac.barcode.regex',
        'Regex for barcodes on patron registration',
        'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.ac.barcode.regex',
        'The Regular Expression for validation on barcodes in patron registration.',
        'coust', 'description'),
    'string', null);

COMMIT;
