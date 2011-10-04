BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0633');

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype ) VALUES
(
        'print.custom_js_file', 'circ',
        oils_i18n_gettext(
            'print.custom_js_file',
            'Printing: Custom Javascript File',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'print.custom_js_file',
            'Full URL path to a Javascript File to be loaded when printing. Should'
            || ' implement a print_custom function for DOM manipulation. Can change'
            || ' the value of the do_print variable to false to cancel printing.',
            'coust',
            'description'
        ),
        'string'
    );

COMMIT;
