BEGIN;

SELECT evergreen.upgrade_deps_block_check('0818', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype ) VALUES (
    'circ.patron_edit.duplicate_patron_check_depth', 'circ',
    oils_i18n_gettext(
        'circ.patron_edit.duplicate_patron_check_depth',
        'Specify search depth for the duplicate patron check in the patron editor',
        'coust',
        'label'),
    oils_i18n_gettext(
        'circ.patron_edit.duplicate_patron_check_depth',
        'When using the patron registration page, the duplicate patron check will use the configured depth to scope the search for duplicate patrons.',
        'coust',
        'description'),
    'integer')
;



COMMIT;
