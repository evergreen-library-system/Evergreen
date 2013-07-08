INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'lib.info_url', 'lib',
    oils_i18n_gettext('lib.info_url',
        'Library information URL (such as "http://example.com/about.html")',
        'coust', 'label'),
    oils_i18n_gettext('lib.info_url',
        'URL for information on this library, such as contact information, hours of operation, and directions. If set, the library name in the copy details section links to that URL. Use a complete URL, such as "http://example.com/hours.html".',
        'coust', 'description'),
    'string', null)
;
