
-- NOTE: beware the use of bare perm IDs in the update_perm's below and in 
-- the 950 seed data file.  Update before merge to match current perm IDs! XXX

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0754', :eg_version);

INSERT INTO permission.perm_list (id, code, description) 
    VALUES ( 
        543, 
        'URL_VERIFY',
        oils_i18n_gettext(
            543, 
            'Allows a user to process and verify ULSs', 
            'ppl', 
            'description'
        )
    );


INSERT INTO permission.perm_list (id, code, description) 
    VALUES ( 
        544, 
        544,
        oils_i18n_gettext(
            544, 
            'Allows a user to configure URL verification org unit settings',
            'ppl', 
            'description'
        )
    );


INSERT INTO permission.perm_list (id, code, description) 
    VALUES ( 
        545, 
        'SAVED_FILTER_DIALOG_FILTERS',
        oils_i18n_gettext(
            545, 
            'Allows users to save and load sets of filters for filter dialogs, available in certain staff interfaces',
            'ppl', 
            'description'
        )
    );


INSERT INTO config.settings_group (name, label)
    VALUES (
        'url_verify',
        oils_i18n_gettext(
            'url_verify',
            'URL Verify',
            'csg',
            'label'
        )
    );

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype, update_perm)
    VALUES (
        'url_verify.url_verification_delay',
        'url_verify',
        oils_i18n_gettext(
            'url_verify.url_verification_delay',
            'Number of seconds to wait between URL test attempts.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'url_verify.url_verification_delay',
            'Throttling mechanism for batch URL verification runs.  Each running process will wait this number of seconds after a URL test before performing the next.',
            'coust',
            'description'
        ),
        'integer',
        544
    );

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype, update_perm)
    VALUES (
        'url_verify.url_verification_max_redirects',
        'url_verify',
        oils_i18n_gettext(
            'url_verify.url_verification_max_redirects',
            'Maximum redirect lookups',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'url_verify.url_verification_max_redirects',
            'For URLs returning 3XX redirects, this is the maximum number of redirects we will follow before giving up.',
            'coust',
            'description'
        ),
        'integer',
        544
    );

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype, update_perm)
    VALUES (
        'url_verify.url_verification_max_wait',
        'url_verify',
        oils_i18n_gettext(
            'url_verify.url_verification_max_wait',
            'Maximum wait time (in seconds) for a URL to lookup',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'url_verify.url_verification_max_wait',
            'If we exceed the wait time, the URL is marked as a "timeout" and the system moves on to the next URL',
            'coust',
            'description'
        ),
        'integer',
        544
    );


INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype, update_perm)
    VALUES (
        'url_verify.verification_batch_size',
        'url_verify',
        oils_i18n_gettext(
            'url_verify.verification_batch_size',
            'Number of URLs to test in parallel',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'url_verify.verification_batch_size',
            'URLs are tested in batches.  This number defines the size of each batch and it directly relates to the number of back-end processes performing URL verification.',
            'coust',
            'description'
        ),
        'integer',
        544
    );


INSERT INTO config.filter_dialog_interface (key, description) VALUES (
    'url_verify',
    oils_i18n_gettext(
        'url_verify',
        'All Link Checker filter dialogs',
        'cfdi',
        'description'
    )
);


INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.grid_columns.url_verify.select_urls',
    'gui',
    FALSE,
    oils_i18n_gettext(
        'ui.grid_columns.url_verify.select_urls',
        'Link Checker''s URL Selection interface''s saved columns',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.grid_columns.url_verify.select_urls',
        'Link Checker''s URL Selection interface''s saved columns',
        'cust',
        'description'
    ),
    'string'
);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.grid_columns.url_verify.review_attempt',
    'gui',
    FALSE,
    oils_i18n_gettext(
        'ui.grid_columns.url_verify.review_attempt',
        'Link Checker''s Review Attempt interface''s saved columns',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.grid_columns.url_verify.review_attempt',
        'Link Checker''s Review Attempt interface''s saved columns',
        'cust',
        'description'
    ),
    'string'
);

COMMIT;

