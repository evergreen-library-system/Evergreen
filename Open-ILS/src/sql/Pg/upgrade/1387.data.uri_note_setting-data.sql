BEGIN;

SELECT evergreen.upgrade_deps_block_check('1387', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'opac.uri_default_note_text', 'opac',
    oils_i18n_gettext('opac.uri_default_note_text',
        'Default text to appear for 856 links if none is present',
        'coust', 'label'),
    oils_i18n_gettext('opac.uri_default_note_text',
        'When no value is present in the 856$z this string will be used instead',
        'coust', 'description'),
    'string', null)
;

COMMIT;

