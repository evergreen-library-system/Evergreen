BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'opac.patron.custom_css', 'opac',
    oils_i18n_gettext('opac.patron.custom_css',
        'Custom CSS for the OPAC',
        'coust', 'label'),
    oils_i18n_gettext('opac.patron.custom_css',
        'Custom CSS for the OPAC',
        'coust', 'description'),
    'string', NULL);

COMMIT;
