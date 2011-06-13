BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0550', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'org.patron_opt_boundary',
    oils_i18n_gettext( 
        'org.patron_opt_boundary',
        'Circ: Patron Opt-In Boundary',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'org.patron_opt_boundary',
        'This determines at which depth above which patrons must be opted in, and below which patrons will be assumed to be opted in.',
        'coust',
        'label'
    ),
    'integer'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'org.patron_opt_default',
    oils_i18n_gettext( 
        'org.patron_opt_default',
        'Circ: Patron Opt-In Default',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'org.patron_opt_default',
        'This is the default depth at which a patron is opted in; it is calculated as an org unit relative to the current workstation.',
        'coust',
        'label'
    ),
    'integer'
);

COMMIT;
